import 'dart:math' as math;
import 'dart:ui';

import '../draw/diagram_curve.dart';
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
    this.lead = 12,
    this.parallelGap = 24,
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

  /// Шаг от рамки, на котором кривая ещё идёт перпендикулярно стороне таблицы:
  /// на этом прямом участке стоят знаки кардинальности.
  final double lead;

  /// Между связями одной пары сущностей вдоль стороны таблицы.
  final double parallelGap;

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

  final parallel = _parallel(diagram.relations);

  var labelHeight = 0.0;
  for (final relation in diagram.relations) {
    if (relation.label.isNotEmpty) {
      labelHeight = math.max(labelHeight, measure.run(relation.label, DiagramTextRole.message).size.height);
    }
  }

  // Раскладка и маршруты. Зазор между рядами растёт под самый большой веер
  // подписей: они встают по пролёту лесенкой, каждой — своя высота и запас.
  // Какие связи выйдут из одной стороны одной таблицы, решают слои, — поэтому
  // сперва раскладываем, а не хватило зазора — раскладываем ещё раз, с нужным.
  var gap = metrics.flow.layerGap;
  late FlowLayering layering;
  late FlowGeometry geometry;
  late List<_Route?> routes;
  late Map<int, (int, int)> fans;
  for (var attempt = 0; attempt < 2; attempt++) {
    layering = layerFlowchart(graph);
    geometry = placeFlowchart(
      graph,
      layering,
      measure,
      metrics: metrics.flow.withLayerGap(gap),
      sizes: {for (final entry in tables.entries) entry.key: entry.value.size},
    );
    routes = [
      for (final chain in layering.chains) _route(chain, geometry, metrics, _spreadOf(parallel[chain.edge], metrics)),
    ];
    fans = _fans(layering.chains, routes, geometry, diagram.relations);

    final crowd = fans.values.fold(1, (most, fan) => math.max(most, fan.$2));
    final needed = (crowd + 1) * (labelHeight + _labelClearance);
    if (needed <= gap) {
      break;
    }
    gap = needed;
  }

  final runs = {for (final label in geometry.labels) label.edge: label.run};
  final lines = <DiagramShape>[];
  final labels = <DiagramShape>[];

  /// Что уже стоит и чего подписи касаться нельзя: таблицы и прежние подписи.
  final placed = [for (final box in geometry.boxes.values) box.rect];
  for (var i = 0; i < layering.chains.length; i++) {
    final chain = layering.chains[i];
    final route = routes[i];
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
        smooth: true,
      ),
    );
    final run = runs[chain.edge];
    if (run != null) {
      // Подписи веера — заранее вразбежку по пролёту: на трети и двух третях,
      // на четвертях… Иначе первая встаёт в середину, и второй не остаётся
      // места ни выше, ни ниже.
      final (place, of) = fans[i] ?? (0, 1);
      labels.add(
        DiagramLabel(run: run, at: _placeLabel(run.size, route, placed, first: (place + 1) / (of + 1)), backdrop: true),
      );
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

/// Маршрут связи — точки кривой — и ломаная по самой кривой, на которой
/// стоит подпись.
typedef _Route = ({List<Offset> points, List<Offset> labelSpan});

/// Где на пролёте пробовать подпись, долей его длины: сперва середина, потом
/// всё дальше от неё. Не ближе четверти к концам — там стоят знаки
/// кардинальности.
const List<double> _labelSpots = [0.5, 0.35, 0.65, 0.25, 0.75];

/// Сколько пустого держать вокруг подписи.
const double _labelClearance = 8;

/// Левый верхний угол подписи размера [size] на маршруте [route].
///
/// Подпись, задевшая уже поставленную или таблицу, едет вдоль своей линии: из
/// одной таблицы связи расходятся медленно, и две подписи на одной высоте
/// слипаются в одну строку. Лесенкой они стоят там, где линии уже разошлись.
/// Места нет нигде — туда, где задевает меньше всего.
Offset _placeLabel(Size size, _Route route, List<Rect> placed, {double first = 0.5}) {
  final span = route.labelSpan;
  final lengths = [0.0];
  for (var i = 1; i < span.length; i++) {
    lengths.add(lengths.last + (span[i] - span[i - 1]).distance);
  }

  /// Точка на пролёте при доле [t] его длины.
  Offset along(double t) {
    final wanted = lengths.last * t;
    for (var i = 1; i < span.length; i++) {
      if (lengths[i] >= wanted) {
        final piece = lengths[i] - lengths[i - 1];
        return Offset.lerp(span[i - 1], span[i], piece == 0 ? 0 : (wanted - lengths[i - 1]) / piece)!;
      }
    }
    return span.last;
  }

  Rect at(double t) => Rect.fromCenter(center: along(t), width: size.width, height: size.height);

  for (final t in [first, ..._labelSpots]) {
    final rect = at(t);
    // Зазор — с букву: подписи вплотную читаются одной строкой.
    if (!placed.any((other) => other.overlaps(rect.inflate(_labelClearance)))) {
      placed.add(rect);

      return rect.topLeft;
    }
  }

  // Места нет нигде — туда, где задевает меньше всего: подпись важнее зазора.
  double overlap(Rect rect) {
    var total = 0.0;
    for (final other in placed) {
      final common = other.intersect(rect.inflate(_labelClearance));
      if (common.width > 0 && common.height > 0) {
        total += common.width * common.height;
      }
    }

    return total;
  }

  final candidates = [
    for (final t in [first, ..._labelSpots]) at(t),
  ];
  final best = candidates.reduce((a, b) => overlap(b) < overlap(a) ? b : a);
  placed.add(best);

  return best.topLeft;
}

/// Насколько сдвинуть концы связи вдоль стороны таблицы: связи одной пары
/// встают веером вокруг середины стороны.
double _spreadOf((int, int)? parallel, ErMetrics metrics) {
  if (parallel == null) {
    return 0;
  }
  final (place, of) = parallel;

  return (place - (of - 1) / 2) * metrics.parallelGap;
}

/// Веера подписей: связи с подписью, выходящие из одной стороны одной таблицы.
/// Для каждой — место в веере слева направо (сверху вниз) и размер веера.
///
/// Подписи веера стоят на пролётах, которые у таблицы ещё рядом: расставленные
/// по одной в середину, они слипаются. Связи одной пары — частный случай.
Map<int, (int, int)> _fans(
  List<FlowChain> chains,
  List<_Route?> routes,
  FlowGeometry geometry,
  List<ErRelation> relations,
) {
  final groups = <String, List<(int, double)>>{};
  for (var i = 0; i < chains.length; i++) {
    final chain = chains[i];
    final route = routes[i];
    final start = chain.cells.first;
    if (route == null || chain.selfLoop || start.isBend || relations[chain.edge].label.isEmpty) {
      continue;
    }
    final rect = geometry.boxes[start.id]!.rect;
    final exit = route.labelSpan.first;
    final side = flowSide(rect, exit);
    // Вдоль стороны: сверху и снизу — по x, сбоку — по y.
    final position = side.dy != 0 ? exit.dx : exit.dy;
    groups.putIfAbsent('${start.id}\u0000$side', () => []).add((i, position));
  }

  return {
    for (final group in groups.values)
      for (final (k, (index, _)) in (group..sort((a, b) => a.$2.compareTo(b.$2))).indexed) index: (k, group.length),
  };
}

/// Связи одной пары сущностей: какая по счёту и сколько их всего.
///
/// Раскладка у них одна, и без разводки линии ложатся друг на друга: одна
/// прячет другую, а подписям некуда разойтись. Так бывает часто — «создал» и
/// «изменил» от одной таблицы к другой. Связи пары встают веером вокруг
/// середины стороны, на [ErMetrics.parallelGap] друг от друга.
Map<int, (int, int)> _parallel(List<ErRelation> relations) {
  final pairs = <String, List<int>>{};
  for (var i = 0; i < relations.length; i++) {
    final relation = relations[i];
    if (relation.from == relation.to) {
      continue;
    }
    // Пара без учёта стороны: `A–B` и `B–A` — та же пара таблиц.
    final key = ([relation.from, relation.to]..sort()).join('\u0000');
    pairs.putIfAbsent(key, () => []).add(i);
  }

  return {
    for (final group in pairs.values)
      for (var k = 0; k < group.length; k++) group[k]: (k, group.length),
  };
}

/// Линия связи: кривая через перегибы геометрии, концами в рамки таблиц.
///
/// У каждого конца — две точки на одной прямой, перпендикулярной стороне
/// таблицы, на [ErMetrics.lead] и вдвое дальше. Кривая `curveBasis` у конца
/// идёт по этой прямой, и потому выходит из таблицы и входит в неё под прямым
/// углом, а знак кардинальности лежит на прямом участке, а не на изгибе
/// (`docs/spec/mermaid.md`, §7а).
///
/// Подпись — на **первом пролёте** самой кривой, от рамки до следующей точки
/// раскладки, а не посередине между центрами, как в графе: у высокой таблицы
/// центр далеко внутри, и подпись съезжала к самой рамке, туда, где две
/// расходящиеся связи ещё рядом.
_Route? _route(FlowChain chain, FlowGeometry geometry, ErMetrics metrics, double spread) {
  if (chain.selfLoop) {
    // Шаг петли — графа: под него геометрия оставила место сбоку.
    final points = flowLoop(geometry.boxes[chain.cells.single.id]!.rect, lead: metrics.flow.lead, straight: true);

    return (points: points, labelSpan: diagramSample(diagramBasis(points)));
  }
  if (chain.cells.length < 2) {
    return null;
  }

  Offset centreOf(FlowCell cell) => cell.isBend ? geometry.bends[cell]! : geometry.boxes[cell.id]!.rect.center;

  final centres = [for (final cell in chain.cells) centreOf(cell)];
  final first = chain.cells.first;
  final last = chain.cells.last;
  final points = [...centres];

  // Поперёк линии от первой ячейки к последней: в эту сторону сдвигаются оба
  // конца параллельной связи, и линии пары не перекрещиваются.
  final along = centres.last - centres.first;
  final across = along.distance == 0 ? const Offset(1, 0) : Offset(-along.dy, along.dx) / along.distance;

  // Конец в рамке и две точки перпендикулярно её стороне; ближе, если рамки
  // стоят тесно, — иначе точки разошлись бы мимо друг друга.
  List<Offset> lead(FlowCell cell, Offset towards) {
    final rect = geometry.boxes[cell.id]!.rect;
    var exit = flowExit(geometry.boxes[cell.id]!, towards);
    final outward = flowSide(rect, exit);
    if (spread != 0) {
      // Вдоль стороны, в ту же сторону, что [across], и не дальше её краёв.
      final side = Offset(outward.dy.abs(), outward.dx.abs());
      final sign = (across.dx * side.dx + across.dy * side.dy) < 0 ? -1.0 : 1.0;
      final shifted = exit + side * spread * sign;
      exit = Offset(
        shifted.dx.clamp(rect.left + metrics.padding, rect.right - metrics.padding),
        shifted.dy.clamp(rect.top + metrics.padding, rect.bottom - metrics.padding),
      );
      // Сдвинутый конец остаётся на своей стороне рамки.
      if (outward.dx != 0) {
        exit = Offset(outward.dx > 0 ? rect.right : rect.left, exit.dy);
      } else {
        exit = Offset(exit.dx, outward.dy > 0 ? rect.bottom : rect.top);
      }
    }
    final step = math.min(metrics.lead, (towards - exit).distance / 6);
    return flowLead(exit, outward, step, straight: true);
  }

  if (!first.isBend) {
    points.replaceRange(0, 1, lead(first, centres[1]));
  }
  if (!last.isBend) {
    points.replaceRange(points.length - 1, points.length, lead(last, centres[centres.length - 2]).reversed);
  }

  // Пролёт подписи — по кривой до точки, ближайшей к следующей ячейке.
  final sampled = diagramSample(diagramBasis(points));
  final next = chain.cells.length > 2 ? centres[1] : sampled.last;
  var end = sampled.length - 1;
  for (var i = 0; i < sampled.length; i++) {
    if ((sampled[i] - next).distance < (sampled[end] - next).distance) {
      end = i;
    }
  }

  // Рисуем в настоящую сторону: перевёрнутость живёт только внутри раскладки.
  return (points: chain.reversed ? points.reversed.toList() : points, labelSpan: sampled.sublist(0, end + 1));
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
