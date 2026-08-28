import 'package:fc_api/fc_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Что перетаскивание помнит между запусками.
class DragAndDropSettings implements Serializable {
  DragAndDropSettings({this.dropIntoSamePanel = false});

  /// Пускать ли бросок обратно в ту панель, из которой тащат.
  ///
  /// По умолчанию нет: копировать каталог сам в себя незачем, а рамка вокруг
  /// панели-источника обещает работу, которой не будет, — и сбивает с толку
  /// ровно в тот момент, когда человек смотрит, куда целится. Кому эта повадка
  /// нужна (перетащить в подкаталог, не уходя из панели), включает.
  bool dropIntoSamePanel;

  @override
  void fromMap(Map<String, dynamic> m) {
    dropIntoSamePanel = extract(dropIntoSamePanel, m['dropIntoSamePanel']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['dropIntoSamePanel'] = dropIntoSamePanel;
  }
}

/// Перетаскивание мышью средствами самой системы.
///
/// Нативная часть живёт в раннере (`macos/Runner/MainFlutterWindow.swift`) и
/// делает ровно то, чего нельзя сделать из Flutter: подписывается на
/// перетаскивание над окном и присылает сюда точку и пути. Всё остальное —
/// кто под курсором, можно ли туда бросать, что делать с брошенным — решается
/// здесь и в панелях.
///
/// Модуль платформенный, поэтому и стоит рядом с локальной файловой системой, а
/// не в `dependency/`: без своего раннера канала не существует. Выключишь его —
/// пропадёт возможность, и ничего больше: панели про перетаскивание не знают.
class SystemDragAndDrop implements FcModule {
  const SystemDragAndDrop();

  @override
  String get id => 'fc.dnd';

  @override
  String get title => 'Drag and drop';

  @override
  void install(FcRegistry registry) {
    final settings = registry.settings;
    DragAndDropSettings settingsOf() => settings.section(DragAndDropSettings.new);

    registry.service<DragAndDrop>(
      // Место под временные копии — то же, которым пользуются просмотрщик и
      // открытие внешней программой: файл из архива сперва оказывается на
      // диске, иначе отдавать наружу нечего.
      (services) => SystemDropService(settings: settingsOf, staging: services.resolve<StagingArea>()),
    );

    // Приложение службе нужно ровно для одного: сказать человеку, если
    // обещанное выложить не вышло. Молчать тут нельзя — со стороны это
    // выглядит как «перетащил, и ничего не произошло».
    registry.startup((context) => _TellFailuresCommand(context));

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.flag(
          'dropIntoSamePanel',
          title: 'Drop into the same panel',
          description: 'Allow dropping files back into the panel they are dragged from',
          read: () => settingsOf().dropIntoSamePanel,
          write: (value) => settingsOf().dropIntoSamePanel = value,
        ),
      ], save: settings.save),
    );
  }
}

/// Отдаёт службе приложение — чтобы было кому пожаловаться.
class _TellFailuresCommand extends AppCommand {
  _TellFailuresCommand(this.context);

  final FcContext context;

  @override
  String get id => 'dnd.install';

  @override
  String get label => 'Install drag and drop';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext _) async {
    final service = context.resolve<DragAndDrop>();
    if (service is SystemDropService) {
      service.tellFailuresTo(context.app);
    }
  }
}

/// Приёмник, зарегистрировавший себя у службы.
class _Target {
  _Target(this.owner, this.spotAt, this.onDrop);

  /// Место, которому принадлежит приёмник, — панель. По нему и решается, не в
  /// себя ли тащат.
  final Object owner;

  /// Что у этого приёмника в точке (в глобальных координатах); null — ничего.
  final DropSpot? Function(Offset global) spotAt;

  final Future<void> Function(DropSpot spot, DropPayload payload) onDrop;

  /// Что сейчас под курсором у **этого** приёмника: по нему рисуется подсветка.
  final ValueNotifier<DropSpot?> hovered = ValueNotifier<DropSpot?>(null);
}

/// Служба перетаскивания поверх канала раннера.
class SystemDropService implements DragAndDrop {
  SystemDropService({MethodChannel? channel, DragAndDropSettings Function()? settings, StagingArea? staging})
    : _channel = channel ?? const MethodChannel(channelName),
      _settings = settings ?? DragAndDropSettings.new,
      _staging = staging;

  /// Где заводить временные копии; null — заводить негде, и наружу поедет
  /// только то, у чего есть настоящий путь.
  final StagingArea? _staging;

  /// Обещанное: что именно система попросит выложить, когда оно ей
  /// понадобится. Ключ — имя, под которым обещали.
  final Map<String, FsNode> _promised = {};

  /// Обещанное, которого ещё не спрашивали.
  ///
  /// По нему и живёт аренда источника: пока здесь пусто, держать архив
  /// смонтированным незачем, а пока не пусто — нельзя отпускать, откуда бы ни
  /// пришла просьба и когда бы она ни пришла.
  final Set<String> _unread = {};

  /// Копии этого перетаскивания и аренда источника: и то и другое живёт ровно
  /// столько, сколько сессия.
  LocalCopySession? _copies;
  ProviderLease? _lease;

  final DragAndDropSettings Function() _settings;

  /// Идёт ли своя сессия перетаскивания.
  ///
  /// Пока идёт, источники молчат: система уже тащит, и просить её об этом
  /// второй раз нечего.
  bool get dragging => _draggingFrom != null;

  /// Место, из которого тащат прямо сейчас; null — тащат не у нас.
  ///
  /// Держится от начала своей сессии до её конца — о том и о другом сообщает
  /// нативная часть. Угадывать это по событиям окна нечем: наружу бросают в
  /// чужом окне, и оттуда к нам не приходит ничего.
  Object? _draggingFrom;

  /// Имя канала — единственное, о чём договариваются Dart и раннер.
  static const String channelName = 'flex_commander/drop';

  final MethodChannel _channel;

  /// Приёмники в порядке появления. Спор решается в пользу последнего: вложенный
  /// объявляется позже внешнего, а бросают всегда в то, что видно.
  final List<_Target> _targets = [];

  Future<dynamic> _onEvent(MethodCall call) async {
    switch (call.method) {
      case 'dragEntered':
      case 'dragUpdated':
        _hover(_pointOf(call));
      case 'dragExited':
        _hover(null);
      case 'dragBegan':
        // Начало своей сессии: с этого мгновения известно, откуда тащат.
        break;
      case 'dragEnded':
        _draggingFrom = null;
        _hover(null);
        // Убирать обещанное здесь **нельзя**: система просит содержимое уже
        // после конца сессии, и порядок этих двух событий ничем не закреплён.
        // Пока убирали — работало через раз, и «через раз» тут худшее из
        // возможного: человек не понимает, от чего это зависит.
        //
        // Аренда — по тому же правилу: отпускаем, только если спрашивать уже
        // нечего. Иначе человек, вышедший из архива, пока файл ехал, остался
        // бы с пустой копией.
        await _releaseIfRead();
      case 'writePromise':
        // Система попросила обещанное: только теперь его и выкладываем.
        return _writePromise(call);
      case 'drop':
        await _drop(_pointOf(call), _pathsOf(call), moves: _flagOf(call, 'move'));
    }
    return null;
  }

  static Offset? _pointOf(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is! Map) {
      return null;
    }
    final x = arguments['x'];
    final y = arguments['y'];
    return x is num && y is num ? Offset(x.toDouble(), y.toDouble()) : null;
  }

  static bool _flagOf(MethodCall call, String name) {
    final arguments = call.arguments;
    return arguments is Map && arguments[name] == true;
  }

  static List<String> _pathsOf(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is! Map) {
      return const [];
    }
    final paths = arguments['paths'];
    return paths is List ? [for (final path in paths) '$path'] : const [];
  }

  /// Кому из приёмников достаётся точка. Подсветка гаснет у всех остальных.
  _Target? _hover(Offset? point) {
    _Target? winner;
    DropSpot? spot;
    if (point != null) {
      for (final target in _targets) {
        // В себя не бросают: место, где жест начался, приёмником себе не
        // бывает — если только человек не сказал обратное настройкой.
        if (identical(target.owner, _draggingFrom) && !_settings().dropIntoSamePanel) {
          continue;
        }
        final candidate = target.spotAt(point);
        if (candidate != null) {
          winner = target;
          spot = candidate;
        }
      }
    }
    for (final target in _targets) {
      target.hovered.value = identical(target, winner) ? spot : null;
    }
    return winner;
  }

  Future<void> _drop(Offset? point, List<String> paths, {required bool moves}) async {
    final winner = _hover(point);
    final spot = winner?.hovered.value;
    // Подсветка гаснет **до** работы: окно хода работы поднимется поверх, и
    // светящаяся под ним строка выглядела бы как незакрытый жест.
    _hover(null);
    if (winner == null || spot == null || paths.isEmpty) {
      return;
    }
    await winner.onDrop(spot, DropPayload(paths: paths, moves: moves));
  }

  /// Кому жаловаться, если обещанное выложить не вышло.
  Application? _app;

  void tellFailuresTo(Application app) => _app = app;

  /// Выкладывает обещанное во временный файл и отвечает путём к нему.
  ///
  /// Пока никто не попросил, ничего и не читается: перетащить файл из архива
  /// на рабочий стол и передумать по дороге — обычное дело, и распаковывать
  /// ради этого незачем.
  Future<String?> _writePromise(MethodCall call) async {
    final arguments = call.arguments;
    final id = arguments is Map ? arguments['id'] : null;
    final node = id is String ? _promised[id] : null;
    final staging = _staging;
    if (node == null || staging == null) {
      return null;
    }
    final copies = _copies ??= LocalCopySession(staging, prefix: 'flex_commander_drag');
    try {
      final path = await copies.localPathOf(node);
      // Прочитано — держать источник больше незачем, даже если жест давно
      // кончился.
      _unread.remove(id);
      await _releaseIfRead();
      return path;
    } catch (error) {
      // Со стороны неудача выглядит как «перетащил, и ничего не произошло»:
      // система молча бросает то, чего ей не дали. Сказать об этом обязаны мы.
      _app?.toasts.show('Could not hand over «${node.name}»: $error');
      return null;
    }
  }

  /// Отпускает источник, если всё обещанное уже прочитано.
  ///
  /// Аренда держится ради одного — чтения содержимого, — и живёт ровно
  /// столько, сколько эта надобность. Не до конца жеста: просьба приходит уже
  /// после него. И не до выхода из архива: ради этого случая она и заведена —
  /// панель вправе уйти, а прочитать мы обязаны.
  Future<void> _releaseIfRead() async {
    if (_unread.isEmpty) {
      await _releaseSource();
    }
  }

  Future<void> _releaseSource() async {
    final lease = _lease;
    _lease = null;
    await lease?.release();
  }

  /// Убирает всё, что осталось от прошлого перетаскивания.
  ///
  /// Зовётся **началом следующего**, а не концом прошлого: система вправе
  /// попросить обещанное после того, как сессия кончилась, и до этой просьбы
  /// ни копии, ни список обещаний трогать нельзя. Заодно так временные файлы
  /// не переживают приложение больше, чем на одно перетаскивание.
  Future<void> _forgetPrevious() async {
    _promised.clear();
    _unread.clear();
    await _releaseSource();
    final copies = _copies;
    _copies = null;
    await copies?.purge();
  }

  /// Имя, под которым обещан объект. Совпадения разводятся числом: система
  /// различает обещания по имени файла, и двух одинаковых ей давать нельзя.
  String _uniqueName(String name) {
    if (!_promised.containsKey(name)) {
      return name;
    }
    for (var i = 2; ; i++) {
      final candidate = '$i-$name';
      if (!_promised.containsKey(candidate)) {
        return candidate;
      }
    }
  }

  @override
  @override
  Widget target({
    required Object owner,
    required DropSpot? Function(Offset local) spotAt,
    required Future<void> Function(DropSpot spot, DropPayload payload) onDrop,
    required Widget Function(BuildContext context, DropSpot? hovered) builder,
  }) {
    return _DropArea(service: this, owner: owner, spotAt: spotAt, onDrop: onDrop, builder: builder);
  }

  @override
  Widget source({
    required Object owner,
    required Widget child,
    required List<FsNode> Function() nodes,
    ProviderLease? Function()? hold,
  }) => _DragSource(service: this, owner: owner, nodes: nodes, hold: hold, child: child);

  /// Просит систему потащить объекты наружу.
  ///
  /// Наружу отдаётся **настоящий путь**: у архива и `ssh` его нет, и отдавать
  /// оттуда нужно обещанные файлы — это отдельная работа
  /// (`spec/drag-and-drop.md`, §7). Пока таких объектов в пачке нет, тащить
  /// нечего, и жест просто ничего не делает.
  Future<bool> beginDrag(Object owner, List<FsNode> nodes, {ProviderLease? Function()? hold}) async {
    await _forgetPrevious();

    final paths = <String>[];
    final promises = <Map<String, Object?>>[];

    for (final node in nodes) {
      if (node is ParentDirNode) {
        continue;
      }
      if (node.provider.capabilities.realFileSystem) {
        paths.add(node.pathString);
        continue;
      }
      // Настоящего пути нет — отдаём обещание. Каталоги пока не обещаем: их
      // выкладка это целый обход, и делается она не здесь
      // (`spec/drag-and-drop.md`, §7).
      if (_staging == null || node is DirectoryNode || node is! FileNode) {
        continue;
      }
      final name = _uniqueName(node.name);
      _promised[name] = node;
      _unread.add(name);
      promises.add({'id': name, 'name': name});
    }

    if (paths.isEmpty && promises.isEmpty) {
      return false;
    }
    // Запоминается **до** вызова: система начинает перетаскивание сразу, и
    // первое же `dragUpdated` придёт раньше, чем сюда вернётся ответ.
    _draggingFrom = owner;
    // Источник держится всё время жеста: пока файл едет в чужое окно, панель
    // вправе уйти куда угодно, а содержимое у неё спросят уже после.
    _lease = hold?.call();
    final started = await _channel.invokeMethod<bool>('beginDrag', {'paths': paths, 'promises': promises}) ?? false;
    if (!started) {
      _draggingFrom = null;
      await _forgetPrevious();
    }
    return started;
  }

  /// Слушать канал начинаем с появлением первого приёмника и перестаём с
  /// уходом последнего.
  ///
  /// Не в конструкторе: службу создаёт сборка приложения, а она случается и
  /// там, где виджетов нет вовсе — в модульных тестах. Канал в такой среде
  /// трогать нельзя, привязки Flutter ещё не существует. Заодно это и честно:
  /// пока принимать некому, слушать нечего.
  void _register(_Target target) {
    if (_targets.isEmpty) {
      _channel.setMethodCallHandler(_onEvent);
    }
    _targets.add(target);
  }

  void _unregister(_Target target) {
    _targets.remove(target);
    target.hovered.dispose();
    if (_targets.isEmpty) {
      _channel.setMethodCallHandler(null);
    }
  }
}

/// Область, принимающая перетаскивание.
class _DropArea extends StatefulWidget {
  const _DropArea({
    required this.service,
    required this.owner,
    required this.spotAt,
    required this.onDrop,
    required this.builder,
  });

  final SystemDropService service;
  final Object owner;
  final DropSpot? Function(Offset local) spotAt;
  final Future<void> Function(DropSpot spot, DropPayload payload) onDrop;
  final Widget Function(BuildContext context, DropSpot? hovered) builder;

  @override
  State<_DropArea> createState() => _DropAreaState();
}

class _DropAreaState extends State<_DropArea> {
  late final _Target _target = _Target(widget.owner, _spotAt, (spot, payload) => widget.onDrop(spot, payload));

  @override
  void initState() {
    super.initState();
    widget.service._register(_target);
  }

  @override
  void dispose() {
    widget.service._unregister(_target);
    super.dispose();
  }

  /// Точка приходит в глобальных координатах — тех же, в которых её меряет
  /// система: у окна без полосы заголовка содержимое начинается с левого
  /// верхнего угла.
  DropSpot? _spotAt(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    final local = box.globalToLocal(global);
    if (local.dx < 0 || local.dy < 0 || local.dx > box.size.width || local.dy > box.size.height) {
      return null;
    }
    return widget.spotAt(local);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DropSpot?>(
      valueListenable: _target.hovered,
      builder: (context, hovered, _) => widget.builder(context, hovered),
    );
  }
}

/// Источник перетаскивания: строка, которую можно утащить.
///
/// Слушает **события указателя**, а не жест. Жест здесь не годится: список
/// прокручивается вертикально, и вертикальную протяжку арена отдаёт прокрутке —
/// файл нельзя было бы утащить ни вверх, ни вниз. События указателя в арене не
/// участвуют вовсе, поэтому решение принимается здесь: сдвинулись дальше порога
/// с зажатой кнопкой — значит тащат.
///
/// Как только система начнёт перетаскивание, мышь перейдёт к ней, и до Flutter
/// движения больше не дойдут: прокрутка, если и успела начаться, дальше не
/// поедет.
class _DragSource extends StatefulWidget {
  const _DragSource({
    required this.service,
    required this.owner,
    required this.nodes,
    required this.hold,
    required this.child,
  });

  final SystemDropService service;
  final Object owner;
  final ProviderLease? Function()? hold;
  final List<FsNode> Function() nodes;
  final Widget child;

  @override
  State<_DragSource> createState() => _DragSourceState();
}

class _DragSourceState extends State<_DragSource> {
  /// Порог в точках: меньше — это дрожание руки при щелчке, а не перетаскивание.
  static const double _threshold = 4;

  /// Откуда ведут. Ставится нажатием — **или первым же движением с зажатой
  /// кнопкой**, если нажатия мы не видели.
  ///
  /// Видеть его мы обязаны не всегда, и это не мелочь: как только система
  /// начинает перетаскивание, мышь переходит к ней, и отпускания кнопки Flutter
  /// не получает вовсе. Он продолжает считать кнопку нажатой — а следующее
  /// **настоящее** нажатие приходит к нам уже движением, потому что для него
  /// кнопка и так была нажата. Отсюда и был дефект: после неудачного броска
  /// потянуть снова не выходило, пока не отпустишь и не нажмёшь заново.
  Offset? _origin;

  void _down(PointerDownEvent event) {
    // Только левая кнопка и только мышь: правая когда-нибудь станет меню, а к
    // сенсорному экрану у файлового менеджера свои вопросы.
    _origin = _isDrag(event.kind, event.buttons) ? event.position : null;
  }

  static bool _isDrag(PointerDeviceKind kind, int buttons) =>
      kind == PointerDeviceKind.mouse && buttons == kPrimaryMouseButton;

  Future<void> _move(PointerMoveEvent event) async {
    // Система уже тащит — просить её об этом второй раз нечего.
    if (widget.service.dragging || !_isDrag(event.kind, event.buttons)) {
      return;
    }
    final origin = _origin ??= event.position;
    if ((event.position - origin).distance < _threshold) {
      return;
    }
    // Попытка израсходована: удастся — тащим, не удастся — отсчёт начнётся
    // заново со следующего движения. Так одна неудача не убивает всё нажатие.
    _origin = null;
    await widget.service.beginDrag(widget.owner, widget.nodes(), hold: widget.hold);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (_) => _origin = null,
      onPointerCancel: (_) => _origin = null,
      child: widget.child,
    );
  }
}
