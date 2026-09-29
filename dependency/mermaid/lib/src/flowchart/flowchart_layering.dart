import 'flowchart_model.dart';

/// Ячейка слоя: настоящий узел или точка перегиба длинного ребра.
///
/// Фиктивные ячейки нужны затем, чтобы дальше — и при упорядочивании, и при
/// маршруте — не было ни одного ребра длиннее одного слоя
/// (`docs/spec/mermaid.md`, §7).
class FlowCell {
  FlowCell.node(this.id, this.layer) : edge = -1;

  FlowCell.bend(this.edge, this.layer) : id = null;

  /// Имя узла; null — перегиб.
  final String? id;

  /// Чьё это ребро; -1 у настоящего узла.
  final int edge;

  /// Номер слоя, считая с нуля.
  final int layer;

  /// Место в слое: считается упорядочиванием.
  int order = 0;

  bool get isBend => id == null;

  @override
  String toString() => isBend ? 'изгиб ребра $edge на слое $layer' : '$id на слое $layer';
}

/// Путь одного ребра по слоям.
class FlowChain {
  FlowChain({required this.edge, required this.reversed, required this.cells, this.selfLoop = false});

  /// Индекс ребра в [FlowchartDiagram.edges].
  final int edge;

  /// Ребро развернули, снимая цикл.
  ///
  /// Рисуется оно всё равно в свою настоящую сторону: перевёрнутость живёт
  /// только внутри раскладки.
  final bool reversed;

  /// Ячейки от меньшего слоя к большему: начало, перегибы, конец.
  final List<FlowCell> cells;

  /// Петля на себя: слоёв не пересекает и в раскладке не участвует.
  final bool selfLoop;
}

/// Слои и порядок внутри них.
class FlowLayering {
  const FlowLayering({required this.layers, required this.chains});

  /// Ячейки по слоям, каждый — в своём порядке.
  final List<List<FlowCell>> layers;

  /// По одной цепочке на ребро исходной модели, в том же порядке.
  final List<FlowChain> chains;

  /// Сколько пересечений между соседними слоями сейчас.
  int get crossings {
    var total = 0;
    for (var i = 0; i + 1 < layers.length; i++) {
      total += _crossingsBetween(i);
    }

    return total;
  }

  int _crossingsBetween(int upper) {
    // Пары «место сверху — место снизу» по всем связям между слоями.
    final pairs = <(int, int)>[];
    for (final chain in chains) {
      for (var i = 0; i + 1 < chain.cells.length; i++) {
        if (chain.cells[i].layer == upper) {
          pairs.add((chain.cells[i].order, chain.cells[i + 1].order));
        }
      }
    }
    pairs.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));

    var count = 0;
    for (var i = 0; i < pairs.length; i++) {
      for (var j = i + 1; j < pairs.length; j++) {
        if (pairs[i].$2 > pairs[j].$2) {
          count++;
        }
      }
    }

    return count;
  }
}

/// Разложить граф по слоям.
///
/// Чистая комбинаторика: ни размеров, ни координат — их считает следующий шаг.
/// Поэтому и проверяется без замера текста вовсе.
FlowLayering layerFlowchart(FlowchartDiagram diagram) => _Layering(diagram).run();

/// Дуга после снятия циклов: всегда из меньшего слоя в больший.
class _Arc {
  const _Arc({required this.edge, required this.from, required this.to, required this.span, required this.reversed});

  final int edge;
  final String from;
  final String to;
  final int span;
  final bool reversed;
}

class _Layering {
  _Layering(this.diagram);

  final FlowchartDiagram diagram;

  /// Сколько проходов упорядочивания. Больше почти не улучшает, а время растёт.
  static const int _sweeps = 4;

  late final List<String> _ids = [for (final node in diagram.nodes) node.id];

  /// Место узла в тексте: с него начинается порядок внутри слоя.
  late final Map<String, int> _declared = {for (var i = 0; i < _ids.length; i++) _ids[i]: i};

  /// Цепочка подграфов вокруг узла, от внешнего к внутреннему.
  late final Map<String, List<int>> _groups = _groupPaths();

  FlowLayering run() {
    final arcs = _removeCycles();
    final layerOf = _assignLayers(arcs);
    final (layers, chains) = _buildCells(arcs, layerOf);

    _order(layers, chains);

    return FlowLayering(layers: layers, chains: chains);
  }

  // --- 1. снятие циклов ---

  /// Обход в глубину в порядке объявления; ребро в узел, который сейчас на
  /// стеке, разворачивается.
  List<_Arc> _removeCycles() {
    final arcs = <_Arc>[];
    final outgoing = <String, List<int>>{for (final id in _ids) id: []};

    for (var i = 0; i < diagram.edges.length; i++) {
      final edge = diagram.edges[i];
      if (edge.from == edge.to) {
        continue;
      }
      outgoing[edge.from]?.add(i);
    }

    final visited = <String>{};
    final onStack = <String>{};
    final reversed = <int>{};

    void walk(String id) {
      visited.add(id);
      onStack.add(id);
      for (final index in outgoing[id] ?? const <int>[]) {
        final to = diagram.edges[index].to;
        if (onStack.contains(to)) {
          reversed.add(index);
          continue;
        }
        if (!visited.contains(to)) {
          walk(to);
        }
      }
      onStack.remove(id);
    }

    for (final id in _ids) {
      if (!visited.contains(id)) {
        walk(id);
      }
    }

    for (var i = 0; i < diagram.edges.length; i++) {
      final edge = diagram.edges[i];
      if (edge.from == edge.to) {
        continue;
      }
      final back = reversed.contains(i);
      arcs.add(
        _Arc(
          edge: i,
          from: back ? edge.to : edge.from,
          to: back ? edge.from : edge.to,
          span: edge.span,
          reversed: back,
        ),
      );
    }

    return arcs;
  }

  // --- 2. слои ---

  /// Длиннейшим путём: слой узла на единицу больше наибольшего слоя
  /// предшественников, а ребро с запрошенной длиной требует не меньше своей.
  Map<String, int> _assignLayers(List<_Arc> arcs) {
    final layerOf = {for (final id in _ids) id: 0};
    final incoming = <String, List<_Arc>>{for (final id in _ids) id: []};
    for (final arc in arcs) {
      incoming[arc.to]?.add(arc);
    }

    // Проходим, пока что-то двигается: граф уже ацикличен, значит проходов не
    // больше числа узлов.
    for (var pass = 0; pass <= _ids.length; pass++) {
      var moved = false;
      for (final id in _ids) {
        for (final arc in incoming[id] ?? const <_Arc>[]) {
          final wanted = layerOf[arc.from]! + arc.span;
          if (wanted > layerOf[id]!) {
            layerOf[id] = wanted;
            moved = true;
          }
        }
      }
      if (!moved) {
        break;
      }
    }

    return layerOf;
  }

  // --- 3. ячейки и фиктивные узлы ---

  (List<List<FlowCell>>, List<FlowChain>) _buildCells(List<_Arc> arcs, Map<String, int> layerOf) {
    final depth = layerOf.values.fold(0, (a, b) => a > b ? a : b) + 1;
    final layers = [for (var i = 0; i < depth; i++) <FlowCell>[]];
    final cellOf = <String, FlowCell>{};

    for (final id in _ids) {
      final cell = FlowCell.node(id, layerOf[id]!);
      cellOf[id] = cell;
      layers[cell.layer].add(cell);
    }

    final chains = <FlowChain?>[for (var i = 0; i < diagram.edges.length; i++) null];

    // Петли на себя слоёв не пересекают: их рисуют отдельно.
    for (var i = 0; i < diagram.edges.length; i++) {
      final edge = diagram.edges[i];
      if (edge.from == edge.to) {
        chains[i] = FlowChain(edge: i, reversed: false, cells: [cellOf[edge.from]!], selfLoop: true);
      }
    }

    for (final arc in arcs) {
      final cells = <FlowCell>[cellOf[arc.from]!];
      for (var layer = layerOf[arc.from]! + 1; layer < layerOf[arc.to]!; layer++) {
        final bend = FlowCell.bend(arc.edge, layer);
        layers[layer].add(bend);
        cells.add(bend);
      }
      cells.add(cellOf[arc.to]!);
      chains[arc.edge] = FlowChain(edge: arc.edge, reversed: arc.reversed, cells: cells);
    }

    return (layers, [for (final chain in chains) chain!]);
  }

  // --- 4. порядок внутри слоя ---

  void _order(List<List<FlowCell>> layers, List<FlowChain> chains) {
    final up = <FlowCell, List<FlowCell>>{};
    final down = <FlowCell, List<FlowCell>>{};

    for (final chain in chains) {
      if (chain.selfLoop) {
        continue;
      }
      for (var i = 0; i + 1 < chain.cells.length; i++) {
        (down[chain.cells[i]] ??= []).add(chain.cells[i + 1]);
        (up[chain.cells[i + 1]] ??= []).add(chain.cells[i]);
      }
    }

    // Начальный порядок — порядок объявления: картинка похожа на то, как автор
    // её писал, а не на то, как легла эвристика.
    for (final layer in layers) {
      layer.sort((a, b) => _initial(a).compareTo(_initial(b)));
    }
    _renumber(layers);
    _keepGroups(layers);

    final best = [
      for (final layer in layers) [...layer],
    ];
    var least = FlowLayering(layers: layers, chains: chains).crossings;

    for (var sweep = 0; sweep < _sweeps; sweep++) {
      _sweep(layers, sweep.isEven ? down : up, downwards: sweep.isEven);
      _keepGroups(layers);

      final now = FlowLayering(layers: layers, chains: chains).crossings;
      if (now < least) {
        least = now;
        for (var i = 0; i < layers.length; i++) {
          best[i] = [...layers[i]];
        }
      }
    }

    // Возвращаем лучшее из виденного: проход мог и ухудшить.
    for (var i = 0; i < layers.length; i++) {
      layers[i]
        ..clear()
        ..addAll(best[i]);
    }
    _renumber(layers);
  }

  /// Один проход: каждый узел — в медиану своих соседей на соседнем слое.
  void _sweep(List<List<FlowCell>> layers, Map<FlowCell, List<FlowCell>> neighbours, {required bool downwards}) {
    final order =
        downwards ? [for (var i = 1; i < layers.length; i++) i] : [for (var i = layers.length - 2; i >= 0; i--) i];

    for (final index in order) {
      final layer = layers[index];
      final median = <FlowCell, double>{for (final cell in layer) cell: _median(neighbours[cell] ?? const [])};

      // Устойчивая сортировка: у кого соседей нет, тот остаётся где был.
      final places = {for (var i = 0; i < layer.length; i++) layer[i]: i};
      layer.sort((a, b) {
        final byMedian = median[a]!.compareTo(median[b]!);

        return byMedian != 0 ? byMedian : places[a]!.compareTo(places[b]!);
      });
      _renumber(layers);
    }
  }

  /// Медиана мест соседей; -1 — соседей нет, и трогать нечего.
  double _median(List<FlowCell> cells) {
    if (cells.isEmpty) {
      return -1;
    }
    final places = [for (final cell in cells) cell.order]..sort();
    final middle = places.length ~/ 2;

    return places.length.isOdd ? places[middle].toDouble() : (places[middle - 1] + places[middle]) / 2;
  }

  /// Члены одного подграфа — подряд.
  ///
  /// Это ограничение, а не свойство: держать их рядом иногда стоит лишних
  /// пересечений. Рамка, разорванная чужим узлом, читается как ошибка
  /// отрисовки, а лишнее пересечение — нет (§7).
  void _keepGroups(List<List<FlowCell>> layers) {
    if (diagram.subgraphs.isEmpty) {
      return;
    }

    for (var i = 0; i < layers.length; i++) {
      layers[i] = _blocks(layers[i], 0);
    }
    _renumber(layers);
  }

  /// Пересобрать слой блоками: каждый подграф — один блок, чужой узел — свой.
  ///
  /// Блоками, а не сравнением по группам: сравнение не двигает узел **без**
  /// группы относительно её членов, и чужой узел так и остаётся вклиненным
  /// между своими — проверка это и показала.
  List<FlowCell> _blocks(List<FlowCell> cells, int depth) {
    final order = <Object>[];
    final blocks = <Object, List<FlowCell>>{};

    for (final cell in cells) {
      final path = _groupsOf(cell);
      // Ключ блока: подграф на этой глубине, а нет его — сама ячейка.
      final Object key = depth < path.length ? path[depth] : cell;
      if (!blocks.containsKey(key)) {
        blocks[key] = [];
        order.add(key);
      }
      blocks[key]!.add(cell);
    }

    double middle(List<FlowCell> block) => block.map((cell) => cell.order).reduce((a, b) => a + b) / block.length;

    final sorted = [...order]..sort((a, b) {
      final left = blocks[a]!;
      final right = blocks[b]!;
      final byMiddle = middle(left).compareTo(middle(right));

      // Середины совпали — вперёд тот, кто и так был выше: иначе блок с чужим
      // узлом посередине менялся бы местами туда-сюда.
      return byMiddle != 0 ? byMiddle : left.first.order.compareTo(right.first.order);
    });

    final result = <FlowCell>[];
    for (final key in sorted) {
      final block = blocks[key]!;
      result.addAll(key is int && block.length > 1 ? _blocks(block, depth + 1) : block);
    }

    return result;
  }

  /// Подграфы вокруг ячейки, от внешнего к внутреннему.
  ///
  /// У перегиба своего подграфа нет; он принадлежит тому, что общий у концов
  /// его ребра, — иначе длинное ребро внутри рамки выталкивало бы её края.
  List<int> _groupsOf(FlowCell cell) {
    if (!cell.isBend) {
      return _groups[cell.id] ?? const [];
    }

    final edge = diagram.edges[cell.edge];
    final from = _groups[edge.from] ?? const <int>[];
    final to = _groups[edge.to] ?? const <int>[];
    final common = <int>[];
    for (var i = 0; i < from.length && i < to.length && from[i] == to[i]; i++) {
      common.add(from[i]);
    }

    return common;
  }

  Map<String, List<int>> _groupPaths() {
    final parent = <int, int>{};
    for (var i = 0; i < diagram.subgraphs.length; i++) {
      for (final inner in diagram.subgraphs[i].subgraphs) {
        final at = diagram.subgraphs.indexWhere((group) => group.id == inner);
        if (at >= 0) {
          parent[at] = i;
        }
      }
    }

    final paths = <String, List<int>>{};
    for (var i = 0; i < diagram.subgraphs.length; i++) {
      final path = <int>[];
      for (int? at = i; at != null; at = parent[at]) {
        path.insert(0, at);
      }
      for (final id in diagram.subgraphs[i].nodes) {
        paths[id] = path;
      }
    }

    return paths;
  }

  /// Чем сортировать в самом начале: узел — местом объявления, перегиб —
  /// номером своего ребра, и перегибы после узлов.
  int _initial(FlowCell cell) => cell.isBend ? _ids.length + cell.edge : (_declared[cell.id] ?? 0);

  void _renumber(List<List<FlowCell>> layers) {
    for (final layer in layers) {
      for (var i = 0; i < layer.length; i++) {
        layer[i].order = i;
      }
    }
  }
}
