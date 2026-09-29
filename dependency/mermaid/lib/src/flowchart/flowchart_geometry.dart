import 'dart:math' as math;
import 'dart:ui';

import '../draw/diagram_text.dart';
import 'flowchart_layering.dart';
import 'flowchart_model.dart';

/// Размеры раскладки графа. Числами, а не ролями темы: это устройство одной
/// картинки (`docs/spec/mermaid.md`, §7).
class FlowMetrics {
  const FlowMetrics({
    this.margin = 12,
    this.padding = 8,
    this.layerGap = 36,
    this.cellGap = 20,
    this.minWidth = 44,
    this.minHeight = 28,
    this.slant = 10,
    this.lip = 5,
    this.frameInset = 10,
    this.frameGap = 6,
    this.labelGap = 6,
  });

  /// Поле вокруг всей картинки.
  final double margin;

  /// Отступ подписи внутри фигуры.
  final double padding;

  /// Между соседними слоями.
  final double layerGap;

  /// Между соседями внутри слоя.
  final double cellGap;

  /// Наименьшая фигура: узел с коротким именем не должен выходить точкой.
  final double minWidth;
  final double minHeight;

  /// Скос параллелограмма и трапеции по каждому краю.
  final double slant;

  /// Высота «крышки» цилиндра.
  final double lip;

  /// Насколько рамка подграфа шире своего содержимого.
  final double frameInset;

  /// Между заголовком рамки и содержимым.
  final double frameGap;

  /// Между подписью ребра и самим ребром.
  final double labelGap;
}

/// Узел на своём месте.
class FlowBox {
  const FlowBox({required this.id, required this.shape, required this.rect, required this.text});

  final String id;
  final FlowShape shape;

  /// Где стоит фигура целиком.
  final Rect rect;

  /// Замеренная подпись; рисовать её по центру [rect].
  final DiagramTextRun text;
}

/// Рамка подграфа.
class FlowFrame {
  const FlowFrame({required this.id, required this.rect, required this.title, required this.titleAt});

  final String id;
  final Rect rect;
  final DiagramTextRun title;

  /// Левый верхний угол заголовка.
  final Offset titleAt;
}

/// Подпись ребра на своём месте.
class FlowEdgeLabel {
  const FlowEdgeLabel({required this.edge, required this.run, required this.at});

  final int edge;
  final DiagramTextRun run;

  /// Левый верхний угол.
  final Offset at;
}

/// Где что стоит. Маршруты рёбер считает следующий шаг: ему нужны и фигуры, и
/// перегибы, а они здесь.
class FlowGeometry {
  const FlowGeometry({
    required this.size,
    required this.layering,
    required this.boxes,
    required this.bends,
    required this.frames,
    required this.labels,
  });

  final Size size;
  final FlowLayering layering;

  /// Узлы по имени.
  final Map<String, FlowBox> boxes;

  /// Центры перегибов длинных рёбер.
  final Map<FlowCell, Offset> bends;

  final List<FlowFrame> frames;

  /// Подписи рёбер; у ребра без подписи её здесь нет.
  final List<FlowEdgeLabel> labels;
}

/// Расставить граф по местам.
///
/// Чистый расчёт: на входе модель, слои и замер текста, на выходе прямоугольники
/// и размер. Ни холста, ни виджетов.
FlowGeometry placeFlowchart(
  FlowchartDiagram diagram,
  FlowLayering layering,
  DiagramTextMeasure measure, {
  FlowMetrics metrics = const FlowMetrics(),
}) => _Geometry(diagram, layering, measure, metrics).run();

class _Geometry {
  _Geometry(this.diagram, this.layering, this.measure, this.metrics);

  final FlowchartDiagram diagram;
  final FlowLayering layering;
  final DiagramTextMeasure measure;
  final FlowMetrics metrics;

  /// Сколько раз подтягиваем узлы к медиане соседей.
  static const int _passes = 4;

  late final bool _horizontal =
      diagram.direction == FlowDirection.leftRight || diagram.direction == FlowDirection.rightLeft;

  late final bool _mirrored =
      diagram.direction == FlowDirection.bottomUp || diagram.direction == FlowDirection.rightLeft;

  final Map<String, DiagramTextRun> _text = {};
  final Map<String, Size> _shapeSize = {};
  final Map<int, DiagramTextRun> _edgeText = {};

  /// Середина ячейки вдоль слоя.
  final Map<FlowCell, double> _along = {};

  FlowGeometry run() {
    _measureNodes();
    _measureEdges();

    final thickness = _thicknesses();
    final gaps = _gaps();
    final offsets = _offsets(thickness, gaps);

    _placeAlong();
    _centreLayers();

    final total = offsets.last + thickness.last;
    final boxes = <String, FlowBox>{};
    final bends = <FlowCell, Offset>{};

    for (final cells in layering.layers) {
      for (final cell in cells) {
        final centre = _centreOf(cell, offsets, thickness, total + metrics.margin);
        if (cell.isBend) {
          bends[cell] = centre;
          continue;
        }
        final shape = _shapeSize[cell.id]!;
        boxes[cell.id!] = FlowBox(
          id: cell.id!,
          shape: _nodeOf(cell.id!).shape,
          rect: Rect.fromCenter(center: centre, width: shape.width, height: shape.height),
          text: _text[cell.id]!,
        );
      }
    }

    final frames = _frames(boxes);
    final labels = _labels(boxes, bends);

    // Рамка подграфа выступает над своими узлами на заголовок, а подпись ребра
    // — вбок: размер считается по тому, что получилось, а не по одним слоям.
    return _normalise(boxes, bends, frames, labels);
  }

  /// Сдвинуть всё в поле и объявить размер по тому, что вышло.
  FlowGeometry _normalise(
    Map<String, FlowBox> boxes,
    Map<FlowCell, Offset> bends,
    List<FlowFrame> frames,
    List<FlowEdgeLabel> labels,
  ) {
    Rect? bounds;
    void add(Rect rect) => bounds = bounds == null ? rect : bounds!.expandToInclude(rect);

    for (final box in boxes.values) {
      add(box.rect);
    }
    for (final frame in frames) {
      add(frame.rect);
    }
    for (final label in labels) {
      add(label.at & label.run.size);
    }
    for (final centre in bends.values) {
      add(Rect.fromCenter(center: centre, width: 1, height: 1));
    }

    if (bounds == null) {
      return FlowGeometry(
        size: Size.zero,
        layering: layering,
        boxes: const {},
        bends: const {},
        frames: const [],
        labels: const [],
      );
    }

    final shift = Offset(metrics.margin - bounds!.left, metrics.margin - bounds!.top);

    return FlowGeometry(
      size: Size(bounds!.width + metrics.margin * 2, bounds!.height + metrics.margin * 2),
      layering: layering,
      boxes: {
        for (final entry in boxes.entries)
          entry.key: FlowBox(
            id: entry.value.id,
            shape: entry.value.shape,
            rect: entry.value.rect.shift(shift),
            text: entry.value.text,
          ),
      },
      bends: {for (final entry in bends.entries) entry.key: entry.value + shift},
      frames: [
        for (final frame in frames)
          FlowFrame(id: frame.id, rect: frame.rect.shift(shift), title: frame.title, titleAt: frame.titleAt + shift),
      ],
      labels: [for (final label in labels) FlowEdgeLabel(edge: label.edge, run: label.run, at: label.at + shift)],
    );
  }

  // --- замер ---

  void _measureNodes() {
    for (final node in diagram.nodes) {
      final run = measure.run(node.text.join('\n'), DiagramTextRole.note);
      _text[node.id] = run;
      _shapeSize[node.id] = _sizeOf(node.shape, run.size);
    }
  }

  void _measureEdges() {
    for (var i = 0; i < diagram.edges.length; i++) {
      final label = diagram.edges[i].label;
      if (label.isNotEmpty) {
        _edgeText[i] = measure.run(label.join('\n'), DiagramTextRole.message);
      }
    }
  }

  /// Сколько места нужно фигуре под подпись такого размера.
  ///
  /// Форма добавляет своё: ромбу нужно вдвое больше по обеим сторонам — текст в
  /// него вписан по диагоналям; кругу — диагональ подписи; скошенным — скос по
  /// краям. Иначе буквы вылезают за фигуру, а это хуже, чем крупная фигура.
  Size _sizeOf(FlowShape shape, Size text) {
    final width = text.width + metrics.padding * 2;
    final height = text.height + metrics.padding * 2;

    final wanted = switch (shape) {
      FlowShape.rect || FlowShape.rounded || FlowShape.flag => Size(width, height),
      FlowShape.subroutine => Size(width + metrics.slant * 2, height),
      FlowShape.stadium => Size(width + height / 2, height),
      FlowShape.hexagon => Size(width + height / 2, height),
      FlowShape.cylinder => Size(width, height + metrics.lip * 2),
      FlowShape.circle => Size.square(
        math.sqrt(text.width * text.width + text.height * text.height) + metrics.padding * 2,
      ),
      FlowShape.rhombus => Size(width * 2, height * 2),
      FlowShape.parallelogram ||
      FlowShape.parallelogramAlt ||
      FlowShape.trapezoid ||
      FlowShape.trapezoidAlt => Size(width + metrics.slant * 2, height),
    };

    return Size(math.max(wanted.width, metrics.minWidth), math.max(wanted.height, metrics.minHeight));
  }

  FlowNode _nodeOf(String id) => diagram.nodes.firstWhere((node) => node.id == id);

  /// Размер ячейки вдоль слоя и поперёк.
  double _alongSize(FlowCell cell) {
    if (cell.isBend) {
      return 0;
    }
    final size = _shapeSize[cell.id]!;

    return _horizontal ? size.height : size.width;
  }

  double _acrossSize(FlowCell cell) {
    if (cell.isBend) {
      return 0;
    }
    final size = _shapeSize[cell.id]!;

    return _horizontal ? size.width : size.height;
  }

  // --- слои поперёк ---

  List<double> _thicknesses() => [
    for (final cells in layering.layers) cells.fold(0.0, (widest, cell) => math.max(widest, _acrossSize(cell))),
  ];

  /// Зазоры между слоями: подпись ребра раздвигает свой, а не наезжает на узлы.
  List<double> _gaps() {
    final gaps = [for (var i = 0; i + 1 < layering.layers.length; i++) metrics.layerGap];

    for (final chain in layering.chains) {
      final run = _edgeText[chain.edge];
      if (run == null || chain.selfLoop || chain.cells.length < 2) {
        continue;
      }
      final needed = (_horizontal ? run.size.width : run.size.height) + metrics.labelGap * 2;
      final at = chain.cells.first.layer;
      if (at < gaps.length) {
        gaps[at] = math.max(gaps[at], needed);
      }
    }

    return gaps;
  }

  List<double> _offsets(List<double> thickness, List<double> gaps) {
    final offsets = <double>[];
    var at = metrics.margin;
    for (var i = 0; i < thickness.length; i++) {
      offsets.add(at);
      at += thickness[i] + (i < gaps.length ? gaps[i] : 0);
    }

    return offsets;
  }

  // --- места вдоль слоя ---

  void _placeAlong() {
    for (final cells in layering.layers) {
      var at = metrics.margin;
      for (final cell in cells) {
        _along[cell] = at + _alongSize(cell) / 2;
        at += _alongSize(cell) + metrics.cellGap;
      }
    }

    final up = <FlowCell, List<FlowCell>>{};
    final down = <FlowCell, List<FlowCell>>{};
    for (final chain in layering.chains) {
      if (chain.selfLoop) {
        continue;
      }
      for (var i = 0; i + 1 < chain.cells.length; i++) {
        (down[chain.cells[i]] ??= []).add(chain.cells[i + 1]);
        (up[chain.cells[i + 1]] ??= []).add(chain.cells[i]);
      }
    }

    for (var pass = 0; pass < _passes; pass++) {
      final downwards = pass.isEven;
      final indexes =
          downwards
              ? [for (var i = 1; i < layering.layers.length; i++) i]
              : [for (var i = layering.layers.length - 2; i >= 0; i--) i];

      for (final index in indexes) {
        _pull(layering.layers[index], downwards ? up : down);
      }
    }
  }

  /// Подтянуть слой к медианам соседей, не нарушив ни порядка, ни зазоров.
  void _pull(List<FlowCell> cells, Map<FlowCell, List<FlowCell>> neighbours) {
    if (cells.isEmpty) {
      return;
    }

    final wanted = [for (final cell in cells) _medianOf(neighbours[cell] ?? const []) ?? _along[cell]!];

    // Слева направо: не ближе зазора к предыдущему. Так держится и порядок.
    final places = List<double>.filled(cells.length, 0);
    places[0] = wanted.first;
    for (var i = 1; i < cells.length; i++) {
      final least = places[i - 1] + _alongSize(cells[i - 1]) / 2 + metrics.cellGap + _alongSize(cells[i]) / 2;
      places[i] = math.max(wanted[i], least);
    }

    // Справа налево: кого сдвинули дальше, чем он хотел, — подтянуть обратно.
    for (var i = cells.length - 2; i >= 0; i--) {
      final most = places[i + 1] - _alongSize(cells[i + 1]) / 2 - metrics.cellGap - _alongSize(cells[i]) / 2;
      places[i] = math.max(math.min(places[i], most), wanted[i] < places[i] ? wanted[i] : places[i]);
    }

    for (var i = 0; i < cells.length; i++) {
      _along[cells[i]] = places[i];
    }
  }

  double? _medianOf(List<FlowCell> cells) {
    if (cells.isEmpty) {
      return null;
    }
    final places = [for (final cell in cells) _along[cell]!]..sort();
    final middle = places.length ~/ 2;

    return places.length.isOdd ? places[middle] : (places[middle - 1] + places[middle]) / 2;
  }

  /// Сдвинуть всё вдоль слоёв к началу.
  void _centreLayers() {
    var least = double.infinity;
    var most = -double.infinity;

    for (final cells in layering.layers) {
      for (final cell in cells) {
        least = math.min(least, _along[cell]! - _alongSize(cell) / 2);
        most = math.max(most, _along[cell]! + _alongSize(cell) / 2);
      }
    }
    if (!least.isFinite) {
      return;
    }

    final shift = metrics.margin - least;
    for (final cells in layering.layers) {
      for (final cell in cells) {
        _along[cell] = _along[cell]! + shift;
      }
    }
  }

  // --- отображение осей ---

  /// Куда превращается пара «слой, место в слое».
  ///
  /// Меняются местами **оси**, а не готовые координаты: размер узла считается
  /// по подписи, а подпись вместе с картинкой не поворачивается (§7).
  Offset _centreOf(FlowCell cell, List<double> offsets, List<double> thickness, double total) {
    final along = _along[cell]!;
    var across = offsets[cell.layer] + thickness[cell.layer] / 2;
    if (_mirrored) {
      across = total - across;
    }

    return _horizontal ? Offset(across, along) : Offset(along, across);
  }

  // --- рамки подграфов ---

  List<FlowFrame> _frames(Map<String, FlowBox> boxes) {
    final frames = <String, FlowFrame>{};
    final order = _byDepth();

    for (final index in order) {
      final group = diagram.subgraphs[index];
      Rect? bounds;

      void add(Rect rect) => bounds = bounds == null ? rect : bounds!.expandToInclude(rect);

      for (final id in group.nodes) {
        final box = boxes[id];
        if (box != null) {
          add(box.rect);
        }
      }
      for (final inner in group.subgraphs) {
        final frame = frames[inner];
        if (frame != null) {
          add(frame.rect);
        }
      }
      if (bounds == null) {
        continue;
      }

      final title = measure.run(group.text.join('\n'), DiagramTextRole.blockLabel);
      final rect = Rect.fromLTRB(
        bounds!.left - metrics.frameInset,
        bounds!.top - metrics.frameInset - title.size.height - metrics.frameGap,
        bounds!.right + metrics.frameInset,
        bounds!.bottom + metrics.frameInset,
      );

      frames[group.id] = FlowFrame(
        id: group.id,
        rect: rect,
        title: title,
        titleAt: Offset(rect.left + metrics.frameInset, rect.top + metrics.frameGap / 2),
      );
    }

    return [
      for (var i = 0; i < diagram.subgraphs.length; i++)
        if (frames[diagram.subgraphs[i].id] != null) frames[diagram.subgraphs[i].id]!,
    ];
  }

  /// Подграфы от самых глубоких к внешним: внешняя рамка обязана знать
  /// размеры вложенных.
  List<int> _byDepth() {
    final depth = <int, int>{};
    final parent = <int, int>{};
    for (var i = 0; i < diagram.subgraphs.length; i++) {
      for (final inner in diagram.subgraphs[i].subgraphs) {
        final at = diagram.subgraphs.indexWhere((group) => group.id == inner);
        if (at >= 0) {
          parent[at] = i;
        }
      }
    }
    for (var i = 0; i < diagram.subgraphs.length; i++) {
      var level = 0;
      for (int? at = parent[i]; at != null; at = parent[at]) {
        level++;
      }
      depth[i] = level;
    }

    return [for (var i = 0; i < diagram.subgraphs.length; i++) i]..sort((a, b) => depth[b]!.compareTo(depth[a]!));
  }

  // --- подписи рёбер ---

  List<FlowEdgeLabel> _labels(Map<String, FlowBox> boxes, Map<FlowCell, Offset> bends) {
    final labels = <FlowEdgeLabel>[];

    for (final chain in layering.chains) {
      final run = _edgeText[chain.edge];
      if (run == null || chain.selfLoop || chain.cells.length < 2) {
        continue;
      }

      // Посередине первого пролёта: там ребро идёт между слоями, и место под
      // подпись уже раздвинуто.
      final from = _pointOf(chain.cells.first, boxes, bends);
      final to = _pointOf(chain.cells[1], boxes, bends);
      final centre = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);

      labels.add(
        FlowEdgeLabel(
          edge: chain.edge,
          run: run,
          at: Offset(centre.dx - run.size.width / 2, centre.dy - run.size.height / 2),
        ),
      );
    }

    return labels;
  }

  Offset _pointOf(FlowCell cell, Map<String, FlowBox> boxes, Map<FlowCell, Offset> bends) =>
      cell.isBend ? bends[cell]! : boxes[cell.id]!.rect.center;
}
