import 'package:fc_api/fc_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
    registry.service<DragAndDrop>((services) => SystemDropService());
  }
}

/// Приёмник, зарегистрировавший себя у службы.
class _Target {
  _Target(this.spotAt, this.onDrop);

  /// Что у этого приёмника в точке (в глобальных координатах); null — ничего.
  final DropSpot? Function(Offset global) spotAt;

  final Future<void> Function(DropSpot spot, DropPayload payload) onDrop;

  /// Что сейчас под курсором у **этого** приёмника: по нему рисуется подсветка.
  final ValueNotifier<DropSpot?> hovered = ValueNotifier<DropSpot?>(null);
}

/// Служба перетаскивания поверх канала раннера.
class SystemDropService implements DragAndDrop {
  SystemDropService({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

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
    required DropSpot? Function(Offset local) spotAt,
    required Future<void> Function(DropSpot spot, DropPayload payload) onDrop,
    required Widget Function(BuildContext context, DropSpot? hovered) builder,
  }) {
    return _DropArea(service: this, spotAt: spotAt, onDrop: onDrop, builder: builder);
  }

  /// Отдача наружу ещё не сделана: пока это просто содержимое.
  ///
  /// Возвращать здесь заглушку честнее, чем не иметь метода вовсе: панели
  /// объявят себя источником один раз, а научится он позже
  /// (`spec/drag-and-drop.md`, §8).
  @override
  Widget source({required Widget child, required List<FsNode> Function() nodes}) => child;

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
  const _DropArea({required this.service, required this.spotAt, required this.onDrop, required this.builder});

  final SystemDropService service;
  final DropSpot? Function(Offset local) spotAt;
  final Future<void> Function(DropSpot spot, DropPayload payload) onDrop;
  final Widget Function(BuildContext context, DropSpot? hovered) builder;

  @override
  State<_DropArea> createState() => _DropAreaState();
}

class _DropAreaState extends State<_DropArea> {
  late final _Target _target = _Target(_spotAt, (spot, payload) => widget.onDrop(spot, payload));

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
