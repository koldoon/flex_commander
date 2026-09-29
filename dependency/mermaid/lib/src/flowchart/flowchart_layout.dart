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
    // тонет внутри узла.
    points[0] = _exit(chain.cells.first, points[1]);
    points[points.length - 1] = _exit(chain.cells.last, points[points.length - 2]);

    // Рисуем в настоящую сторону: перевёрнутость живёт только внутри раскладки.
    final route = chain.reversed ? points.reversed.toList() : points;

    return [
      DiagramPath(
        points: route,
        head: _head(edge.head),
        tail: _head(edge.tail),
        dashed: edge.line == FlowLine.dotted,
        thick: edge.line == FlowLine.thick,
      ),
    ];
  }

  /// Петля на себя: сбоку от узла и обратно в него.
  DiagramShape _loop(FlowChain chain, FlowEdge edge) {
    final rect = geometry.boxes[chain.cells.single.id]!.rect;
    final out = rect.width / 2;

    return DiagramPath(
      points: [
        Offset(rect.right, rect.center.dy - rect.height / 4),
        Offset(rect.right + out, rect.center.dy - rect.height / 4),
        Offset(rect.right + out, rect.center.dy + rect.height / 4),
        Offset(rect.right, rect.center.dy + rect.height / 4),
      ],
      head: _head(edge.head),
      dashed: edge.line == FlowLine.dotted,
      thick: edge.line == FlowLine.thick,
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

    final box = geometry.boxes[cell.id]!;
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
          DiagramFigure(
            path: Path()..addOval(Rect.fromLTWH(rect.left, rect.top, rect.width, metrics.lip * 2)),
            ink: DiagramInk.faint,
            filled: false,
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
