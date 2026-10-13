import 'dart:math' as math;
import 'dart:ui';

import '../draw/diagram_layout.dart';
import '../draw/diagram_text.dart';
import '../flowchart/flowchart_geometry.dart';
import '../flowchart/flowchart_layering.dart';
import '../flowchart/flowchart_layout.dart';
import '../flowchart/flowchart_model.dart';
import 'er_model.dart';

/// Размеры таблицы сущности. Числами, а не ролями темы: это устройство одной
/// картинки (`docs/spec/mermaid.md`, §7а).
class ErMetrics {
  const ErMetrics({
    this.padding = 8,
    this.rowPadding = 3,
    this.columnGap = 12,
    this.minWidth = 64,
    this.flow = const FlowMetrics(layerGap: 84, cellGap: 40),
  });

  /// Поле шапки и боков таблицы.
  final double padding;

  /// Поле строки атрибута сверху и снизу.
  final double rowPadding;

  /// Между колонками таблицы.
  final double columnGap;

  /// Самая узкая таблица: сущность с коротким именем не выходит точкой.
  final double minWidth;

  /// Раскладка графа: зазоры шире, чем у `flowchart`, — на концах связей
  /// стоят знаки кардинальности, и им нужно место.
  final FlowMetrics flow;
}

/// Разложить ER-диаграмму.
///
/// Своего алгоритма нет: сущности и связи переводятся в граф, и дальше работают
/// те же слои и места, что у `flowchart` (§7). Таблицу меряет эта раскладка и
/// отдаёт её размер графу.
DiagramLayout layoutErDiagram(ErDiagram diagram, DiagramTextMeasure measure, {ErMetrics metrics = const ErMetrics()}) {
  if (diagram.entities.isEmpty) {
    return DiagramLayout.empty;
  }

  final tables = {for (final entity in diagram.entities) entity.id: _Table.measure(entity, measure, metrics)};
  final graph = FlowchartDiagram(
    direction: diagram.direction,
    nodes: [
      for (final entity in diagram.entities) FlowNode(id: entity.id, label: [entity.label]),
    ],
    edges: [
      for (final relation in diagram.relations)
        FlowEdge(
          from: relation.from,
          to: relation.to,
          line: relation.identifying ? FlowLine.solid : FlowLine.dotted,
          head: FlowEnd.none,
          label: relation.label.isEmpty ? const [] : [relation.label],
        ),
    ],
    subgraphs: const [],
  );

  final layering = layerFlowchart(graph);
  final geometry = placeFlowchart(
    graph,
    layering,
    measure,
    metrics: metrics.flow,
    sizes: {for (final entry in tables.entries) entry.key: entry.value.size},
  );

  final runs = {for (final label in geometry.labels) label.edge: label.run};
  final lines = <DiagramShape>[];
  final labels = <DiagramShape>[];

  /// Что уже стоит и чего подписи касаться нельзя: таблицы и прежние подписи.
  final placed = [for (final box in geometry.boxes.values) box.rect];
  for (final chain in layering.chains) {
    final route = _route(chain, geometry);
    if (route == null) {
      continue;
    }
    final relation = diagram.relations[chain.edge];
    lines.add(
      DiagramPath(
        points: route.points,
        head: _headOf(relation.toCard),
        tail: _headOf(relation.fromCard),
        dashed: !relation.identifying,
      ),
    );
    final run = runs[chain.edge];
    if (run != null) {
      labels.add(DiagramLabel(run: run, at: _placeLabel(run.size, route, placed), backdrop: true));
    }
  }

  final shapes = <DiagramShape>[
    // Связи — под таблицами: таблица закрывает собой то, что под неё зашло.
    ...lines,
    for (final entity in diagram.entities) ...tables[entity.id]!.draw(geometry.boxes[entity.id]!.rect, metrics),
    // Подписи связей — поверх всего и на подложке, как в графе.
    ...labels,
  ];

  return DiagramLayout(size: geometry.size, shapes: shapes);
}

/// Знак кардинальности на конце линии.
DiagramHead _headOf(ErCard card) => switch (card) {
  ErCard.exactlyOne => DiagramHead.exactlyOne,
  ErCard.zeroOrOne => DiagramHead.zeroOrOne,
  ErCard.oneOrMore => DiagramHead.oneOrMore,
  ErCard.zeroOrMore => DiagramHead.zeroOrMore,
};

/// Маршрут связи и отрезок, на котором стоит её подпись.
typedef _Route = ({List<Offset> points, Offset labelFrom, Offset labelTo});

/// Где на отрезке пробовать подпись: сперва середина, потом всё дальше от неё.
/// Не ближе четверти к концам — там стоят знаки кардинальности.
const List<double> _labelSpots = [0.5, 0.35, 0.65, 0.25, 0.75];

/// Левый верхний угол подписи размера [size] на маршруте [route].
///
/// Подпись, задевшая уже поставленную или таблицу, едет вдоль своей линии: из
/// одной таблицы связи расходятся медленно, и две подписи на одной высоте
/// слипаются в одну строку. Лесенкой они стоят там, где линии уже разошлись.
/// Места нет нигде — остаётся середина: подпись важнее зазора.
Offset _placeLabel(Size size, _Route route, List<Rect> placed) {
  Rect at(double t) =>
      Rect.fromCenter(center: Offset.lerp(route.labelFrom, route.labelTo, t)!, width: size.width, height: size.height);

  for (final t in _labelSpots) {
    final rect = at(t);
    if (!placed.any((other) => other.overlaps(rect.inflate(3)))) {
      placed.add(rect);

      return rect.topLeft;
    }
  }

  final middle = at(0.5);
  placed.add(middle);

  return middle.topLeft;
}

/// Линия связи: через перегибы геометрии, концами в рамки таблиц.
///
/// Подпись — на **видимом** первом отрезке, между рамкой и следующей точкой, а
/// не посередине между центрами, как в графе. Таблица высокая, её центр далеко
/// внутри, и от середины между центрами подпись съезжала к самой рамке — туда,
/// где две расходящиеся связи ещё рядом, и их подписи слипались.
_Route? _route(FlowChain chain, FlowGeometry geometry) {
  if (chain.selfLoop) {
    final loop = flowLoop(geometry.boxes[chain.cells.single.id]!.rect);

    return (points: loop, labelFrom: loop[1], labelTo: loop[2]);
  }
  if (chain.cells.length < 2) {
    return null;
  }

  Offset centreOf(FlowCell cell) => cell.isBend ? geometry.bends[cell]! : geometry.boxes[cell.id]!.rect.center;

  final points = [for (final cell in chain.cells) centreOf(cell)];
  final first = chain.cells.first;
  final last = chain.cells.last;
  if (!first.isBend) {
    points[0] = flowExit(geometry.boxes[first.id]!, points[1]);
  }
  if (!last.isBend) {
    points[points.length - 1] = flowExit(geometry.boxes[last.id]!, points[points.length - 2]);
  }

  // Рисуем в настоящую сторону: перевёрнутость живёт только внутри раскладки.
  return (points: chain.reversed ? points.reversed.toList() : points, labelFrom: points[0], labelTo: points[1]);
}

/// Таблица сущности: шапка с именем и строки атрибутов колонками
/// «тип | имя | ключи | комментарий».
class _Table {
  _Table._(this.title, this.cells, this.columns, this.headerHeight, this.rowHeight, this.size);

  /// Замерить таблицу. Ширина колонки — по самому широкому значению в ней;
  /// колонка, где пусто у всех, места не занимает.
  factory _Table.measure(ErEntity entity, DiagramTextMeasure measure, ErMetrics metrics) {
    final title = measure.run(entity.label, DiagramTextRole.participant);

    final cells = [
      for (final attribute in entity.attributes)
        [
          _cell(measure, attribute.type, DiagramTextRole.note),
          _cell(measure, attribute.name, DiagramTextRole.note),
          _cell(measure, attribute.keys.map((key) => key.keyword).join(', '), DiagramTextRole.blockLabel),
          _cell(measure, attribute.comment, DiagramTextRole.blockLabel),
        ],
    ];

    final columns = List<double>.filled(4, 0);
    var rowText = 0.0;
    for (final row in cells) {
      for (var i = 0; i < row.length; i++) {
        final run = row[i];
        if (run != null) {
          columns[i] = math.max(columns[i], run.size.width);
          rowText = math.max(rowText, run.size.height);
        }
      }
    }

    final used = columns.where((width) => width > 0).toList();
    final body = used.isEmpty ? 0.0 : used.reduce((a, b) => a + b) + metrics.columnGap * (used.length - 1);
    final width = [
      metrics.minWidth,
      title.size.width + metrics.padding * 2,
      body + metrics.padding * 2,
    ].reduce(math.max);

    final headerHeight = title.size.height + metrics.padding * 2;
    final rowHeight = rowText + metrics.rowPadding * 2;

    return _Table._(
      title,
      cells,
      columns,
      headerHeight,
      rowHeight,
      Size(width, headerHeight + rowHeight * cells.length),
    );
  }

  static DiagramTextRun? _cell(DiagramTextMeasure measure, String text, DiagramTextRole role) =>
      text.isEmpty ? null : measure.run(text, role);

  final DiagramTextRun title;

  /// Строки атрибутов; пустая ячейка — `null`.
  final List<List<DiagramTextRun?>> cells;

  /// Ширина каждой из четырёх колонок; ноль — колонки нет.
  final List<double> columns;

  final double headerHeight;
  final double rowHeight;
  final Size size;

  /// Фигуры таблицы, стоящей в [rect].
  List<DiagramShape> draw(Rect rect, ErMetrics metrics) {
    final header = Rect.fromLTWH(rect.left, rect.top, rect.width, headerHeight);
    final shapes = <DiagramShape>[
      DiagramBox(rect: rect, radius: 2, ink: DiagramInk.fill),
      // Шапка инвертирована, как шапка участника: имя видно первым (§9).
      DiagramBox(rect: header, radius: 2, ink: DiagramInk.plate),
      DiagramLabel(
        run: title,
        at: Offset(header.center.dx - title.size.width / 2, header.center.dy - title.size.height / 2),
      ),
    ];

    for (var row = 0; row < cells.length; row++) {
      final top = rect.top + headerHeight + rowHeight * row;
      if (row > 0) {
        shapes.add(DiagramPath(points: [Offset(rect.left, top), Offset(rect.right, top)], ink: DiagramInk.faint));
      }

      var x = rect.left + metrics.padding;
      for (var column = 0; column < columns.length; column++) {
        if (columns[column] == 0) {
          continue;
        }
        final run = cells[row][column];
        if (run != null) {
          shapes.add(DiagramLabel(run: run, at: Offset(x, top + (rowHeight - run.size.height) / 2)));
        }
        x += columns[column] + metrics.columnGap;
      }
    }

    return shapes;
  }
}
