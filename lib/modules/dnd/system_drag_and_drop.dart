import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
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
class SystemDragAndDrop implements FcFrontendModule {
  const SystemDragAndDrop();

  @override
  String get id => 'fc.dnd';

  @override
  String get title => 'Drag and drop';

  @override
  void installFrontend(FrontendRegistry registry) {
    final settings = registry.settings;
    DragAndDropSettings settingsOf() => settings.section(DragAndDropSettings.new);

    registry.service<DragAndDrop>((services) => SystemDropService(settings: settingsOf));

    // Приложение службе нужно ровно для одного: сказать человеку, если
    // обещанное выложить не вышло. Молчать тут нельзя — со стороны это
    // выглядит как «перетащил, и ничего не произошло».
    registry.startup((context) => _TellFailuresCommand(context));

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.flag(
          'dropIntoSamePanel',
          defaultValue: false,
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
  SystemDropService({MethodChannel? channel, DragAndDropSettings Function()? settings})
    : _channel = channel ?? const MethodChannel(channelName),
      _settings = settings ?? DragAndDropSettings.new;

  /// Обещанное: что именно система попросит выложить, когда оно ей
  /// понадобится. Ключ — имя, под которым обещали.
  ///
  /// Строками, а не узлами: читается обещанное **по пути**, и ядро само
  /// откроет то, из чего читает, — даже если панель за это время ушла из
  /// архива. Аренды здесь поэтому нет вовсе
  /// (`docs/spec/client-server.md`, §7).
  final Map<String, FileEntry> _promised = {};

  /// Область, из которой тащат: под ней и показывается полоса работы, если
  /// выкладка окажется долгой.
  ViewportPosition? _sourceArea;

  var _nextRun = 0;

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

  /// Выкладывает обещанное — **сразу туда, куда просит приёмник**.
  ///
  /// Пока никто не попросил, ничего не читается: перетащить файл из архива на
  /// рабочий стол и передумать по дороге — обычное дело, и распаковывать ради
  /// этого незачем.
  ///
  /// Путь назначения приходит от системы, и он у всех разный: Finder называет
  /// папку, куда бросили, а редактор или мессенджер — свой временный каталог.
  /// Писать через свою временную копию было бы вторым проходом по диску — на
  /// большом файле это ровно вдвое дольше и ни за чем.
  Future<bool> _writePromise(MethodCall call) async {
    final arguments = call.arguments;
    final id = arguments is Map ? arguments['id'] : null;
    final path = arguments is Map ? arguments['path'] : null;
    final entry = id is String ? _promised[id] : null;
    if (entry == null || path is! String) {
      return false;
    }

    try {
      await _extract(entry, path);
      return true;
    } on OperationCanceled {
      // Отменил человек — сказать ему об этом было бы странно.
      return false;
    } catch (error) {
      // Со стороны неудача выглядит как «перетащил, и ничего не произошло»:
      // система молча бросает то, чего ей не дали. Сказать об этом обязаны мы.
      _app?.toasts.show('Could not hand over «${entry.name}»: $error');
      return false;
    }
  }

  /// Читает объект в файл, показывая это обычной работой.
  ///
  /// Работа настоящая: у неё полоса под панелью-источником и отмена. Распаковка
  /// гигабайта из архива идёт заметное время, и молчать о ней нельзя — со
  /// стороны молчание неотличимо от зависания.
  Future<void> _extract(FileEntry entry, String path) async {
    final operation = TaskOperation<void, void>((op, _) => _copyInto(entry, path, op));
    final app = _app;
    final area = _sourceArea;
    final runId = 'dnd.promise#${_nextRun++}';

    if (app != null) {
      app.operations.register(OperationRun(runId: runId, operation: operation, title: 'Extracting «${entry.name}»'));
      if (area != null) {
        app.operations.sendToBackground(runId, owner: area);
      }
    }
    try {
      await operation.run(null);
    } finally {
      app?.operations.forget(runId);
    }
  }

  /// Поток из ядра в файл — с отчётом о байтах и проверкой отмены.
  ///
  /// Читается **по пути**: жест давно кончился, и панель за это время вправе
  /// была уйти хоть из архива. Ядро разберёт путь заново и само подержит то,
  /// из чего читает, — ровно на время чтения.
  Future<void> _copyInto(FileEntry entry, String path, TaskOperation<void, void> op) async {
    final app = _app;
    if (app == null) {
      throw FsError(entry.path, FsErrorKind.notSupported);
    }

    final source = app.contentAt(entry).read();
    final file = File(path);
    final sink = file.openWrite();
    var written = 0;
    try {
      await for (final chunk in source) {
        op.checkCanceled();
        sink.add(chunk);
        written += chunk.length;
        op.report(
          itemName: entry.name,
          bytesTransferred: written,
          bytesTotal: entry.size >= 0 ? entry.size : null,
          itemBytesTransferred: written,
          itemBytesTotal: entry.size >= 0 ? entry.size : null,
        );
      }
      await sink.flush();
    } catch (_) {
      // Недописанный файл выглядит как целый: отменили или сорвалось — убираем
      // сразу, иначе в чужой папке останется обрубок.
      await sink.close();
      if (file.existsSync()) {
        await file.delete();
      }
      rethrow;
    }
    await sink.close();
  }

  /// Забывает прошлое перетаскивание.
  ///
  /// Зовётся **началом следующего**, а не концом прошлого: система вправе
  /// попросить обещанное после того, как сессия кончилась, и до этой просьбы
  /// список обещаний трогать нельзя.
  ///
  /// Убирать при этом нечего: пишем мы сразу в цель, и своих временных файлов
  /// у перетаскивания не остаётся вовсе.
  void _forgetPrevious() => _promised.clear();

  /// Под какой панелью показывать полосу работы; null — источник не панель.
  ViewportPosition? _areaOf(Object owner) {
    final view = _app?.view;
    if (view == null) {
      return null;
    }
    for (final position in const [ViewportPosition.left, ViewportPosition.right]) {
      if (identical(view.panelAt(position), owner)) {
        return position;
      }
    }
    return null;
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
  Widget source({required Object owner, required Widget child, required List<FileEntry> Function() entries}) =>
      _DragSource(service: this, owner: owner, entries: entries, child: child);

  /// Просит систему потащить объекты наружу.
  ///
  /// Наружу отдаётся **настоящий путь**: у архива и `ssh` его нет, и отдавать
  /// оттуда нужно обещанные файлы — это отдельная работа
  /// (`spec/drag-and-drop.md`, §7). Пока таких объектов в пачке нет, тащить
  /// нечего, и жест просто ничего не делает.
  Future<bool> beginDrag(Object owner, List<FileEntry> entries) async {
    _forgetPrevious();

    final paths = <String>[];
    final promises = <Map<String, Object?>>[];

    for (final entry in entries) {
      if (entry.isParent) {
        continue;
      }
      if (entry.realPath.isNotEmpty) {
        paths.add(entry.realPath);
        continue;
      }
      // Настоящего пути нет — отдаём обещание. Каталоги пока не обещаем: их
      // выкладка это целый обход, и делается она не здесь
      // (`spec/drag-and-drop.md`, §7).
      if (entry.isDirectory) {
        continue;
      }
      final name = _uniqueName(entry.name);
      _promised[name] = entry;
      promises.add({'id': name, 'name': name});
    }

    if (paths.isEmpty && promises.isEmpty) {
      return false;
    }
    // Запоминается **до** вызова: система начинает перетаскивание сразу, и
    // первое же `dragUpdated` придёт раньше, чем сюда вернётся ответ.
    _draggingFrom = owner;
    _sourceArea = _areaOf(owner);
    final started = await _channel.invokeMethod<bool>('beginDrag', {'paths': paths, 'promises': promises}) ?? false;
    if (!started) {
      _draggingFrom = null;
      _forgetPrevious();
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
  const _DragSource({required this.service, required this.owner, required this.entries, required this.child});

  final SystemDropService service;
  final Object owner;
  final List<FileEntry> Function() entries;
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
    // Только левая кнопка и только мышь: правая помечает
    // (`spec/mouse-marking.md`), а к сенсорному экрану у файлового менеджера
    // свои вопросы.
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
    await widget.service.beginDrag(widget.owner, widget.entries());
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
