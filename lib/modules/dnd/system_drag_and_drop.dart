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

    registry.service<DragAndDrop>((services) => SystemDropService(settings: settingsOf));

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

  final DragAndDropSettings Function() _settings;

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
      case 'drop':
        await _drop(_pointOf(call), _pathsOf(call));
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

  Future<void> _drop(Offset? point, List<String> paths) async {
    final winner = _hover(point);
    final spot = winner?.hovered.value;
    // Подсветка гаснет **до** работы: окно хода работы поднимется поверх, и
    // светящаяся под ним строка выглядела бы как незакрытый жест.
    _hover(null);
    if (winner == null || spot == null || paths.isEmpty) {
      return;
    }
    await winner.onDrop(spot, DropPayload(paths: paths));
  }

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
  Widget source({required Object owner, required Widget child, required List<FsNode> Function() nodes}) =>
      _DragSource(service: this, owner: owner, nodes: nodes, child: child);

  /// Просит систему потащить объекты наружу.
  ///
  /// Наружу отдаётся **настоящий путь**: у архива и `ssh` его нет, и отдавать
  /// оттуда нужно обещанные файлы — это отдельная работа
  /// (`spec/drag-and-drop.md`, §7). Пока таких объектов в пачке нет, тащить
  /// нечего, и жест просто ничего не делает.
  Future<bool> beginDrag(Object owner, List<FsNode> nodes) async {
    final paths = [
      for (final node in nodes)
        if (node is! ParentDirNode && node.provider.capabilities.realFileSystem) node.pathString,
    ];
    if (paths.isEmpty) {
      return false;
    }
    // Запоминается **до** вызова: система начинает перетаскивание сразу, и
    // первое же `dragUpdated` придёт раньше, чем сюда вернётся ответ.
    _draggingFrom = owner;
    final started = await _channel.invokeMethod<bool>('beginDrag', {'paths': paths}) ?? false;
    if (!started) {
      _draggingFrom = null;
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
  const _DragSource({required this.service, required this.owner, required this.nodes, required this.child});

  final SystemDropService service;
  final Object owner;
  final List<FsNode> Function() nodes;
  final Widget child;

  @override
  State<_DragSource> createState() => _DragSourceState();
}

class _DragSourceState extends State<_DragSource> {
  /// Порог в точках: меньше — это дрожание руки при щелчке, а не перетаскивание.
  static const double _threshold = 4;

  Offset? _origin;
  bool _started = false;

  void _down(PointerDownEvent event) {
    // Только левая кнопка и только мышь: правая once станет меню, а к
    // сенсорному экрану у файлового менеджера свои вопросы.
    if (event.kind != PointerDeviceKind.mouse || event.buttons != kPrimaryMouseButton) {
      _origin = null;
      return;
    }
    _origin = event.position;
    _started = false;
  }

  Future<void> _move(PointerMoveEvent event) async {
    final origin = _origin;
    if (_started || origin == null || (event.position - origin).distance < _threshold) {
      return;
    }
    // Пока система не ответила, второй просьбы не шлём: за время ответа
    // придёт ещё десяток движений.
    _started = true;
    // Не начала — значит и не начиналось: пусть следующее движение попробует
    // снова. Иначе одна неудача убивала бы всё нажатие целиком, и тащить
    // приходилось бы, отпустив и взяв заново.
    _started = await widget.service.beginDrag(widget.owner, widget.nodes());
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
