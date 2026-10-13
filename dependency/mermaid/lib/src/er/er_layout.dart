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
    this.portGap = 24,
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

  /// Между концами связей, входящих в одну сторону таблицы (`_ports`).
  final double portGap;

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
  // Слева направо слои стоят столбцами, и поперёк слоя — x, а не y.
  final horizontal = diagram.direction == FlowDirection.leftRight || diagram.direction == FlowDirection.rightLeft;
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
    final ports = _ports(layering.chains, geometry, metrics, horizontal: horizontal);
    final bands = _bands(layering, geometry, horizontal: horizontal);
    routes = [
      for (final chain in layering.chains) _route(chain, geometry, metrics, ports, bands, horizontal: horizontal),
    ];
    fans = _fans(layering.chains, routes, geometry, diagram.relations);

    final crowd = fans.values.fold(1, (most, fan) => math.max(most, fan.$2));
    // Ряд — строка и два зазора: с одним ряды стояли впритык, и малейшая
    // неточность счёта выталкивала подпись на запасное место, к соседке.
    final needed = (crowd + 1) * (labelHeight + _labelClearance * 2);
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
        DiagramLabel(
          run: run,
          at: _placeLabel(run.size, route, placed, horizontal: horizontal, first: (place + 1) / (of + 1)),
          backdrop: true,
        ),
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
const List<double> _labelSpots = [0.5, 0.35, 0.65, 0.25, 0.75, 0.3, 0.7, 0.4, 0.6];

/// Сколько пустого держать вокруг подписи.
const double _labelClearance = 8;

/// Левый верхний угол подписи размера [size] на маршруте [route].
///
/// Подпись, задевшая уже поставленную или таблицу, едет вдоль своей линии: из
/// одной таблицы связи расходятся медленно, и две подписи на одной высоте
/// слипаются в одну строку. Лесенкой они стоят там, где линии уже разошлись.
/// Места нет нигде — туда, где задевает меньше всего.
Offset _placeLabel(Size size, _Route route, List<Rect> placed, {required bool horizontal, double first = 0.5}) {
  final span = route.labelSpan;
  final lengths = [0.0];
  for (var i = 1; i < span.length; i++) {
    lengths.add(lengths.last + (span[i] - span[i - 1]).distance);
  }

  /// Точка на пролёте при доле [t] его длины — когда пролёт не пересекает
  /// рядов (связь внутри ряда) и уровня по высоте у него нет.
  Offset byLength(double t) {
    final wanted = lengths.last * t;
    for (var i = 1; i < span.length; i++) {
      if (lengths[i] >= wanted) {
        final piece = lengths[i] - lengths[i - 1];
        return Offset.lerp(span[i - 1], span[i], piece == 0 ? 0 : (wanted - lengths[i - 1]) / piece)!;
      }
    }
    return span.last;
  }

  // Доля — **уровень поперёк рядов**, а не доля длины кривой: у связей одного
  // веера длины разные — одна уходит далеко вбок, другая идёт почти прямо, — и
  // одинаковая доля длины приходилась на разную высоту, сводя подписи в одну
  // строку. Нашлось на живой схеме. По уровню у каждой подписи веера свой ряд:
  // где её кривая проходит эту высоту, там и подпись.
  double level(Offset point) => horizontal ? point.dx : point.dy;
  final from = level(span.first);
  final to = level(span.last);

  Offset along(double t) {
    if ((to - from).abs() < size.height) {
      return byLength(t);
    }
    final wanted = from + (to - from) * t;
    for (var i = 1; i < span.length; i++) {
      final a = level(span[i - 1]);
      final b = level(span[i]);
      if ((wanted - a) * (wanted - b) <= 0 && a != b) {
        return Offset.lerp(span[i - 1], span[i], (wanted - a) / (b - a))!;
      }
    }
    return byLength(t);
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

/// Где связь выходит из таблицы [box] в сторону [towards].
///
/// К соседнему ряду — **из стороны, обращённой к нему**: сверху вниз связь к
/// таблице ниже выходит снизу, к таблице выше — сверху, слева направо — справа
/// или слева. Место на стороне — там, где её пересекает луч из центра на цель,
/// но не дальше краёв. По одному лучу, как в графе, невысокая таблица отдавала
/// связь к далёкой цели внизу сбоку из **боковой** стороны: линия шла почти
/// горизонтально и задевала соседнюю таблицу того же ряда. Нашлось на живой
/// схеме. Цель в том же ряду — по лучу, как прежде.
Offset _exitFacing(FlowBox box, Offset towards, ErMetrics metrics, {required bool horizontal}) {
  final rect = box.rect;
  final centre = rect.center;

  // Вдоль слоёв: сверху вниз — y, слева направо — x.
  final low = horizontal ? rect.left : rect.top;
  final high = horizontal ? rect.right : rect.bottom;
  final at = horizontal ? towards.dx : towards.dy;
  final double? side = at > high ? high : (at < low ? low : null);
  if (side == null) {
    return flowExit(box, towards);
  }

  // Где луч из центра пересекает эту сторону, — вдоль неё.
  final from = horizontal ? centre.dx : centre.dy;
  final to = horizontal ? towards.dx : towards.dy;
  final share = (side - from) / (to - from);
  final along =
      horizontal ? centre.dy + (towards.dy - centre.dy) * share : centre.dx + (towards.dx - centre.dx) * share;
  final double clamped = along.clamp(
    (horizontal ? rect.top : rect.left) + metrics.padding,
    math.max(
      (horizontal ? rect.top : rect.left) + metrics.padding,
      (horizontal ? rect.bottom : rect.right) - metrics.padding,
    ),
  );

  return horizontal ? Offset(side, clamped) : Offset(clamped, side);
}

/// Концы связей на сторонах таблиц — «порты»: где какая связь входит в
/// таблицу (`docs/spec/mermaid.md`, §7а).
///
/// Конец, посчитанный сам по себе — по направлению на соседнюю точку
/// маршрута, — у узкой таблицы, куда приходит несколько связей, ложится почти
/// в одну точку, и порядок концов расходится с порядком перегибов в слоях:
/// линии перекрещиваются у самой таблицы. Поэтому концы одной стороны
/// собираются вместе, сортируются по тому, откуда подходит линия, — по углу
/// подхода, то есть по естественной точке входа, — и встают с равным шагом
/// [ErMetrics.portGap] вокруг своей естественной середины. Тогда у таблицы
/// линии не пересекаются, если не пересекаются в слоях.
///
/// Одиночный конец стоит, где стоял. Связи одной пары без перегибов — частный
/// случай: соседняя точка у них одна, и порядок решает порядок записи —
/// одинаковый у обеих таблиц, так что пара не перекрещивается.
Map<(FlowChain, bool), Offset> _ports(
  List<FlowChain> chains,
  FlowGeometry geometry,
  ErMetrics metrics, {
  required bool horizontal,
}) {
  Offset centreOf(FlowCell cell) => cell.isBend ? geometry.bends[cell]! : geometry.boxes[cell.id]!.rect.center;

  final groups = <String, List<({FlowChain chain, bool start, Offset natural, Offset towards})>>{};
  for (final chain in chains) {
    if (chain.selfLoop || chain.cells.length < 2) {
      continue;
    }
    for (final start in [true, false]) {
      final cell = start ? chain.cells.first : chain.cells.last;
      if (cell.isBend) {
        continue;
      }
      final towards = centreOf(start ? chain.cells[1] : chain.cells[chain.cells.length - 2]);
      final box = geometry.boxes[cell.id]!;
      final natural = _exitFacing(box, towards, metrics, horizontal: horizontal);
      groups.putIfAbsent('${cell.id}\u0000${flowSide(box.rect, natural)}', () => []).add((
        chain: chain,
        start: start,
        natural: natural,
        towards: towards,
      ));
    }
  }

  final ports = <(FlowChain, bool), Offset>{};
  for (final group in groups.values) {
    final any = group.first;
    final rect = geometry.boxes[(any.start ? any.chain.cells.first : any.chain.cells.last).id]!.rect;
    final outward = flowSide(rect, any.natural);
    // Сверху и снизу концы стоят по x, сбоку — по y.
    final acrossX = outward.dy != 0;
    double along(Offset point) => acrossX ? point.dx : point.dy;
    Offset onSide(double at) =>
        acrossX
            ? Offset(at, outward.dy > 0 ? rect.bottom : rect.top)
            : Offset(outward.dx > 0 ? rect.right : rect.left, at);

    if (group.length == 1) {
      ports[(any.chain, any.start)] = any.natural;
      continue;
    }

    // По углу, под которым линия подходит к таблице, — по естественной точке
    // входа: для прямых в выпуклую фигуру этот порядок пересечений не даёт.
    // Равные — по соседней точке, потом по порядку записи.
    group.sort((a, b) {
      for (final by in [
        along(a.natural).compareTo(along(b.natural)),
        along(a.towards).compareTo(along(b.towards)),
        a.chain.edge.compareTo(b.chain.edge),
      ]) {
        if (by != 0) {
          return by;
        }
      }

      return 0;
    });

    final low = (acrossX ? rect.left : rect.top) + metrics.padding;
    final high = (acrossX ? rect.right : rect.bottom) - metrics.padding;
    final step = math.min(metrics.portGap, math.max(0.0, high - low) / (group.length - 1));
    final span = step * (group.length - 1);
    final middle = group.map((end) => along(end.natural)).reduce((a, b) => a + b) / group.length;
    final from = (middle - span / 2).clamp(low, math.max(low, high - span));

    for (final (k, end) in group.indexed) {
      ports[(end.chain, end.start)] = onSide(from + step * k);
    }
  }

  return ports;
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
/// Полоса каждого слоя поперёк него — от края до края его таблиц: сверху вниз
/// это верх и низ, слева направо — левый и правый край. Слой без таблиц —
/// без полосы.
Map<int, (double, double)> _bands(FlowLayering layering, FlowGeometry geometry, {required bool horizontal}) => {
  for (var i = 0; i < layering.layers.length; i++)
    if (layering.layers[i].any((cell) => !cell.isBend))
      i: layering.layers[i]
          .where((cell) => !cell.isBend)
          .map((cell) => geometry.boxes[cell.id]!.rect)
          .map((rect) => horizontal ? (rect.left, rect.right) : (rect.top, rect.bottom))
          .reduce((a, b) => (math.min(a.$1, b.$1), math.max(a.$2, b.$2))),
};

_Route? _route(
  FlowChain chain,
  FlowGeometry geometry,
  ErMetrics metrics,
  Map<(FlowChain, bool), Offset> ports,
  Map<int, (double, double)> bands, {
  required bool horizontal,
}) {
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

  // Перегиб в слое с таблицами — не точка, а отрезок поперёк всего слоя, от
  // края его полосы до края. Точкой он стоял посередине высоты слоя, и у
  // высокой таблицы линия шла от него наискось, срезая угол прямо под ней —
  // по строкам таблицы. Отрезком она идёт вдоль таблицы своим коридором и
  // выходит из слоя уже за ней. Нашлось на живой схеме.
  final points = <Offset>[centres.first];
  for (var i = 1; i < chain.cells.length - 1; i++) {
    final bend = centres[i];
    final band = bands[chain.cells[i].layer];
    if (band == null) {
      points.add(bend);
      continue;
    }
    final ends = [
      horizontal ? Offset(band.$1, bend.dy) : Offset(bend.dx, band.$1),
      horizontal ? Offset(band.$2, bend.dy) : Offset(bend.dx, band.$2),
    ];
    // Сперва ближний к тому, откуда линия пришла. Каждый конец — дважды:
    // сплайн через точки не проходит, а тянется к ним, и у одиночной срезал
    // угол внутрь — на соседнюю таблицу, мимо которой коридор и идёт. С двойной
    // точкой кривая подходит к ней вплотную и между ними идёт по прямой.
    ends.sort((a, b) => (a - points.last).distance.compareTo((b - points.last).distance));
    points.addAll([ends[0], ends[0], ends[1], ends[1]]);
  }
  points.add(centres.last);
  // Куда смотрят концы: на ближайшую точку маршрута, а не на середину перегиба.
  final towardsStart = points.length > 2 ? points[1] : centres.last;
  final towardsEnd = points.length > 2 ? points[points.length - 2] : centres.first;

  // Конец в рамке и две точки перпендикулярно её стороне; ближе, если рамки
  // стоят тесно, — иначе точки разошлись бы мимо друг друга.
  List<Offset> lead(FlowCell cell, Offset towards, {required bool start}) {
    final rect = geometry.boxes[cell.id]!.rect;
    // Конец — порт своей стороны (`_ports`).
    final exit =
        ports[(chain, start)] ?? _exitFacing(geometry.boxes[cell.id]!, towards, metrics, horizontal: horizontal);
    final outward = flowSide(rect, exit);
    final step = math.min(metrics.lead, (towards - exit).distance / 6);
    return flowLead(exit, outward, step, straight: true);
  }

  if (!first.isBend) {
    points.replaceRange(0, 1, lead(first, towardsStart, start: true));
  }
  if (!last.isBend) {
    points.replaceRange(points.length - 1, points.length, lead(last, towardsEnd, start: false).reversed);
  }

  // Пролёт подписи — по кривой до точки, ближайшей к первой точке за рамкой.
  final sampled = diagramSample(diagramBasis(points));
  final next = chain.cells.length > 2 ? towardsStart : sampled.last;
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
        shapes.add(DiagramPath(points: [Offset(rect.left, top), Offset(rect.right, top)], ink: DiagramInk.divider));
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
