import 'dart:math' as math;
import 'dart:ui';

import '../draw/diagram_layout.dart';
import '../draw/diagram_text.dart';
import 'flowchart_geometry.dart';
import 'flowchart_layering.dart';
import 'flowchart_model.dart';

/// Разложить граф.
///
/// Чистый расчёт: на входе модель и замер текста, на выходе фигуры и размер.
/// Ни холста, ни виджетов здесь нет (`docs/spec/mermaid.md`, §4).
DiagramLayout layoutFlowchart(
  FlowchartDiagram diagram,
  DiagramTextMeasure measure, {
  FlowMetrics metrics = const FlowMetrics(),
}) {
  final layering = layerFlowchart(diagram);
  final geometry = placeFlowchart(diagram, layering, measure, metrics: metrics);

  return _Drawing(diagram, geometry, metrics).run();
}

/// Где ребро выходит из фигуры [box] в сторону [towards]: на её границе, а не
/// в центре, иначе наконечник тонет внутри.
///
/// Общее у графа и ER: таблица сущности — тот же прямоугольник
/// (`docs/spec/mermaid.md`, §7а).
Offset flowExit(FlowBox box, Offset towards) {
  final centre = box.rect.center;
  final direction = towards - centre;
  if (direction.distance == 0) {
    return centre;
  }
  final unit = direction / direction.distance;
  final half = Offset(box.rect.width / 2, box.rect.height / 2);

  final reach = switch (box.shape) {
    // Круг — по радиусу, ромб — по диагоналям, всё прочее — по рамке.
    FlowShape.circle => half.dx,
    FlowShape.rhombus => 1 / (unit.dx.abs() / half.dx + unit.dy.abs() / half.dy),
    _ => math.min(
      unit.dx == 0 ? double.infinity : half.dx / unit.dx.abs(),
      unit.dy == 0 ? double.infinity : half.dy / unit.dy.abs(),
    ),
  };

  return centre + unit * reach;
}

/// Наружу от той стороны [rect], на которой лежит [point].
Offset flowSide(Rect rect, Offset point) {
  final sides = {
    const Offset(-1, 0): (point.dx - rect.left).abs(),
    const Offset(1, 0): (point.dx - rect.right).abs(),
    const Offset(0, -1): (point.dy - rect.top).abs(),
    const Offset(0, 1): (point.dy - rect.bottom).abs(),
  };

  return sides.entries.reduce((a, b) => b.value < a.value ? b : a).key;
}

/// Наружу от фигуры в точке её границы [exit] — нормаль к границе: у круга по
/// радиусу, у ромба — к его грани, у прочих — к стороне рамки.
Offset flowOutward(FlowBox box, Offset exit) {
  final centre = box.rect.center;
  final from = exit - centre;

  switch (box.shape) {
    case FlowShape.circle:
      return from.distance == 0 ? const Offset(0, 1) : from / from.distance;

    case FlowShape.rhombus:
      final normal = Offset(from.dx.sign / (box.rect.width / 2), from.dy.sign / (box.rect.height / 2));
      return normal.distance == 0 ? const Offset(0, 1) : normal / normal.distance;

    default:
      return flowSide(box.rect, exit);
  }
}

/// Начало сглаженной линии: точка на границе и точка по нормали к ней, на
/// [step].
///
/// Кривая `curveBasis` касается отрезка между ними — поэтому выходит из фигуры
/// и входит в неё под прямым углом, а сразу за ним уже изгибается, как у
/// mermaid. Прямой кусок у конца — шестая доля шага, глазу не виден.
///
/// [straight] — две точки по нормали, на шаге и вдвое дальше: тогда кривая у
/// конца идёт по прямой на всю длину шага. Это для знаков кардинальности ER —
/// «воронья лапка» длиной в 15 точек должна лежать на прямой, а не на изгибе
/// (`docs/spec/mermaid.md`, §7а). Стрелке в шесть точек столько прямой не нужно:
/// с ней петля выходила «ступенькой» — прямой кусок и резкий загиб.
List<Offset> flowLead(Offset exit, Offset outward, double step, {bool straight = false}) => [
  exit,
  exit + outward * step,
  if (straight) exit + outward * step * 2,
];

/// Петля на себя: сбоку от фигуры и обратно в неё. Вбок она выступает не
/// дальше четырёх шагов [lead].
///
/// Обычная — как у mermaid: четыре точки, две опоры далеко справа и чуть за
/// краями петли (`flowRoundLoop`). Кривая круглая, без прямых кусков.
///
/// [straight] — для знаков кардинальности ER: начало и конец горизонтально и по
/// прямой на шаг, через [flowLead], чтобы «лапка» легла на прямую.
List<Offset> flowLoop(Rect rect, {double lead = 10, bool straight = false}) {
  final top = Offset(rect.right, rect.center.dy - rect.height / 4);
  final bottom = Offset(rect.right, rect.center.dy + rect.height / 4);

  if (!straight) {
    return flowRoundLoop(top, bottom, lead * 4);
  }

  const right = Offset(1, 0);

  return [
    ...flowLead(top, right, lead, straight: true),
    Offset(rect.right + lead * 4, rect.center.dy),
    ...flowLead(bottom, right, lead, straight: true).reversed,
  ];
}

/// Петля-скоба ⊃ вправо от [top] к [bottom] шириной не больше [reach].
///
/// Уходит горизонтально, по прямой на четверть ширины, круглым поворотом
/// справа и так же горизонтально возвращается: наконечник входит в линию
/// жизни или фигуру ровно поперёк. Поворот — по двум опорам в углах, а не по
/// одной вершине: с одной он стягивался в острый «листок». Первая петля шла
/// по дуге без прямых кусков и возвращалась наискось — направление стрелки
/// было не разобрать.
List<Offset> flowRoundLoop(Offset top, Offset bottom, double reach) {
  final step = Offset(reach / 4, 0);

  return [
    top,
    top + step,
    top + step * 2,
    Offset(top.dx + reach, top.dy),
    Offset(bottom.dx + reach, bottom.dy),
    bottom + step * 2,
    bottom + step,
    bottom,
  ];
}

class _Drawing {
  _Drawing(this.diagram, this.geometry, this.metrics);

  final FlowchartDiagram diagram;
  final FlowGeometry geometry;
  final FlowMetrics metrics;

  DiagramLayout run() {
    if (geometry.boxes.isEmpty) {
      return DiagramLayout.empty;
    }

    final shapes = <DiagramShape>[
      // Рамки подграфов — под всем: они фон, а не содержимое.
      for (final frame in geometry.frames) ..._frame(frame),
      for (final chain in geometry.layering.chains) ..._edge(chain),
      for (final box in _boxesInOrder()) ..._node(box),
      // Подписи рёбер — поверх всего и на подложке: без неё буквы тонут в
      // линиях, которые под ними проходят (§7).
      for (final label in geometry.labels) DiagramLabel(run: label.run, at: label.at, backdrop: true),
    ];

    return DiagramLayout(size: geometry.size, shapes: shapes);
  }

  /// Узлы в порядке объявления: одна и та же врезка обязана давать одну и ту же
  /// картинку, а порядок обхода словаря такого не обещает.
  List<FlowBox> _boxesInOrder() => [
    for (final node in diagram.nodes)
      if (geometry.boxes[node.id] != null) geometry.boxes[node.id]!,
  ];

  // --- рамки ---

  List<DiagramShape> _frame(FlowFrame frame) => [
    DiagramBox(rect: frame.rect, radius: 4, ink: DiagramInk.faint, filled: false),
    DiagramLabel(run: frame.title, at: frame.titleAt, backdrop: true),
  ];

  // --- рёбра ---

  List<DiagramShape> _edge(FlowChain chain) {
    final edge = diagram.edges[chain.edge];

    if (chain.selfLoop) {
      return [_loop(chain, edge)];
    }
    if (chain.cells.length < 2) {
      return const [];
    }

    final points = [
      for (final cell in chain.cells) cell.isBend ? geometry.bends[cell]! : geometry.boxes[cell.id]!.rect.center,
    ];

    // Концы упираются в границу фигуры, а не в её центр: иначе наконечник
    // тонет внутри узла. И у каждого — по две точки по нормали к границе:
    // кривая выходит и входит под прямым углом, как у mermaid.
    List<Offset> lead(FlowCell cell, Offset towards) {
      final exit = _exit(cell, towards);
      if (cell.isBend) {
        return [exit];
      }
      final step = math.min(metrics.lead, (towards - exit).distance / 6);

      // По прямой на шаг: у конца у кривой нулевая кривизна, и стрелка
      // подходит к фигуре под прямым углом на виду, а не только в последней
      // точке. С одной точкой прямой кусок выходил в шестую долю шага, линия
      // сразу загибалась, и под острым углом было не понять, куда стрелка.
      return flowLead(exit, flowOutward(geometry.boxes[cell.id]!, exit), step, straight: true);
    }

    final centres = [...points];
    points
      ..replaceRange(0, 1, lead(chain.cells.first, centres[1]))
      ..replaceRange(points.length - 1, points.length, lead(chain.cells.last, centres[centres.length - 2]).reversed);

    // Рисуем в настоящую сторону: перевёрнутость живёт только внутри раскладки.
    final route = chain.reversed ? points.reversed.toList() : points;

    return [
      DiagramPath(
        points: route,
        head: _head(edge.head),
        tail: _head(edge.tail),
        dashed: edge.line == FlowLine.dotted,
        thick: edge.line == FlowLine.thick,
        smooth: true,
      ),
    ];
  }

  /// Петля на себя: сбоку от узла и обратно в него.
  DiagramShape _loop(FlowChain chain, FlowEdge edge) {
    return DiagramPath(
      points: flowLoop(geometry.boxes[chain.cells.single.id]!.rect, lead: metrics.lead),
      head: _head(edge.head),
      dashed: edge.line == FlowLine.dotted,
      thick: edge.line == FlowLine.thick,
      smooth: true,
    );
  }

  DiagramHead _head(FlowEnd end) => switch (end) {
    FlowEnd.none => DiagramHead.none,
    FlowEnd.arrow => DiagramHead.arrow,
    FlowEnd.circle => DiagramHead.circle,
    FlowEnd.cross => DiagramHead.cross,
  };

  /// Где ребро выходит из ячейки в сторону [towards].
  Offset _exit(FlowCell cell, Offset towards) {
    if (cell.isBend) {
      return geometry.bends[cell]!;
    }

    return flowExit(geometry.boxes[cell.id]!, towards);
  }

  // --- узлы ---

  List<DiagramShape> _node(FlowBox box) {
    final rect = box.rect;
    final shapes = <DiagramShape>[DiagramFigure(path: _pathOf(box), ink: DiagramInk.fill)];

    // Черты, которые фигура добавляет поверх собственной заливки.
    switch (box.shape) {
      case FlowShape.subroutine:
        shapes.addAll([
          DiagramPath(
            points: [Offset(rect.left + metrics.slant, rect.top), Offset(rect.left + metrics.slant, rect.bottom)],
            ink: DiagramInk.faint,
          ),
          DiagramPath(
            points: [Offset(rect.right - metrics.slant, rect.top), Offset(rect.right - metrics.slant, rect.bottom)],
            ink: DiagramInk.faint,
          ),
        ]);

      case FlowShape.cylinder:
        shapes.add(
          // Крышка — залитый овал светлее тела, а не обводка кольцом: так
          // цилиндр читается объёмом, а не двумя наложенными контурами.
          DiagramFigure(
            path: Path()..addOval(Rect.fromLTWH(rect.left, rect.top, rect.width, metrics.lip * 2)),
            ink: DiagramInk.lid,
            outlined: false,
          ),
        );

      default:
        break;
    }

    shapes.add(
      DiagramLabel(
        run: box.text,
        at: Offset(rect.center.dx - box.text.size.width / 2, rect.center.dy - box.text.size.height / 2),
      ),
    );

    return shapes;
  }

  /// Очертание фигуры по её форме.
  Path _pathOf(FlowBox box) {
    final rect = box.rect;
    final slant = metrics.slant;

    Path polygon(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      return path..close();
    }

    return switch (box.shape) {
      FlowShape.rect || FlowShape.subroutine => Path()..addRect(rect),
      FlowShape.rounded => Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6))),
      FlowShape.stadium => Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2))),
      FlowShape.cylinder =>
        Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.elliptical(rect.width / 2, metrics.lip))),
      FlowShape.circle => Path()..addOval(rect),
      FlowShape.rhombus => polygon([
        Offset(rect.center.dx, rect.top),
        Offset(rect.right, rect.center.dy),
        Offset(rect.center.dx, rect.bottom),
        Offset(rect.left, rect.center.dy),
      ]),
      FlowShape.hexagon => polygon([
        Offset(rect.left + rect.height / 2, rect.top),
        Offset(rect.right - rect.height / 2, rect.top),
        Offset(rect.right, rect.center.dy),
        Offset(rect.right - rect.height / 2, rect.bottom),
        Offset(rect.left + rect.height / 2, rect.bottom),
        Offset(rect.left, rect.center.dy),
      ]),
      FlowShape.parallelogram => polygon([
        Offset(rect.left + slant, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right - slant, rect.bottom),
        Offset(rect.left, rect.bottom),
      ]),
      FlowShape.parallelogramAlt => polygon([
        Offset(rect.left, rect.top),
        Offset(rect.right - slant, rect.top),
        Offset(rect.right, rect.bottom),
        Offset(rect.left + slant, rect.bottom),
      ]),
      FlowShape.trapezoid => polygon([
        Offset(rect.left + slant, rect.top),
        Offset(rect.right - slant, rect.top),
        Offset(rect.right, rect.bottom),
        Offset(rect.left, rect.bottom),
      ]),
      FlowShape.trapezoidAlt => polygon([
        Offset(rect.left, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right - slant, rect.bottom),
        Offset(rect.left + slant, rect.bottom),
      ]),
      FlowShape.flag => polygon([
        Offset(rect.left, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right, rect.bottom),
        Offset(rect.left, rect.bottom),
        Offset(rect.left + slant, rect.center.dy),
      ]),
    };
  }
}
