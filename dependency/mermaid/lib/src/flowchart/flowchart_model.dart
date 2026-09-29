/// Модель графа — чистые данные, без Flutter.
///
/// Раскладка читает её и не разбирает текст; разбор её строит и не считает
/// координат. Граница жёсткая нарочно (`docs/spec/mermaid.md`, §4).
library;

/// Куда растёт граф.
///
/// Раскладка считает слой и место в слое, а во что они превращаются — в `x` и
/// `y` или наоборот — решает отображение в конце (`mermaid.md`, §7).
enum FlowDirection {
  /// `TD` и `TB` — сверху вниз. Умолчание.
  topDown('TD'),

  /// `BT` — снизу вверх.
  bottomUp('BT'),

  /// `LR` — слева направо.
  leftRight('LR'),

  /// `RL` — справа налево.
  rightLeft('RL');

  const FlowDirection(this.keyword);

  /// Слово, которым его пишут.
  final String keyword;
}

/// Чем рисуют узел.
///
/// Форму задают скобки вокруг подписи; какие именно — в `mermaid.md`, §7.
enum FlowShape {
  /// `A[текст]` — обычный шаг.
  rect,

  /// `A(текст)` — он же, со скруглением.
  rounded,

  /// `A([текст])` — начало и конец.
  stadium,

  /// `A[[текст]]` — вызов подпрограммы.
  subroutine,

  /// `A[(текст)]` — хранилище.
  cylinder,

  /// `A((текст))` — точка соединения.
  circle,

  /// `A{текст}` — развилка.
  rhombus,

  /// `A{{текст}}` — подготовка.
  hexagon,

  /// `A[/текст/]` — ввод.
  parallelogram,

  /// `A[\текст\]` — вывод.
  parallelogramAlt,

  /// `A[/текст\]` — ручная операция.
  trapezoid,

  /// `A[\текст/]` — она же, перевёрнутая.
  trapezoidAlt,

  /// `A>текст]` — пометка.
  flag,
}

/// Чем нарисована линия ребра.
enum FlowLine {
  /// `-->` — сплошная.
  solid,

  /// `-.->` — пунктир.
  dotted,

  /// `==>` — толстая.
  thick,
}

/// Чем кончается ребро.
enum FlowEnd {
  /// `---` — ничем.
  none,

  /// `-->` — стрелкой.
  arrow,

  /// `--o` — кружком.
  circle,

  /// `--x` — крестиком.
  cross,
}

/// Узел графа.
class FlowNode {
  const FlowNode({required this.id, required this.label, this.shape = FlowShape.rect});

  /// Имя, которым на него ссылаются в рёбрах.
  final String id;

  /// Подпись, строками: их разделяет `<br/>`. Пусто — подписи нет, и рисуют
  /// имя.
  final List<String> label;

  final FlowShape shape;

  /// Что показывать: подпись, а нет её — имя.
  List<String> get text => label.isEmpty ? [id] : label;

  @override
  String toString() => 'FlowNode($id, $shape)';
}

/// Ребро графа.
class FlowEdge {
  const FlowEdge({
    required this.from,
    required this.to,
    this.line = FlowLine.solid,
    this.head = FlowEnd.arrow,
    this.tail = FlowEnd.none,
    this.label = const [],
    this.span = 1,
  });

  final String from;
  final String to;

  final FlowLine line;

  /// Наконечник у [to].
  final FlowEnd head;

  /// Наконечник у [from]; не `none` только у двусторонней стрелки `<-->`.
  final FlowEnd tail;

  /// Подпись, строками.
  final List<String> label;

  /// Сколько слоёв ребро обязано пересечь, не меньше.
  ///
  /// Лишний знак в `--->` прибавляет единицу. Это единственный способ, которым
  /// автор влияет на раскладку, и слушаться его дёшево (`mermaid.md`, §7).
  final int span;

  @override
  String toString() => 'FlowEdge($from -> $to, $line, span $span)';
}

/// Подграф: рамка вокруг своих узлов.
class FlowSubgraph {
  const FlowSubgraph({required this.id, required this.label, required this.nodes, required this.subgraphs});

  /// Имя; по нему на подграф ссылаются рёбра и вложенность.
  final String id;

  /// Заголовок рамки, строками. Пусто — заголовком служит имя.
  final List<String> label;

  /// Прямые члены — узлы.
  final List<String> nodes;

  /// Прямые члены — вложенные подграфы.
  final List<String> subgraphs;

  /// Что писать на рамке.
  List<String> get text => label.isEmpty ? [id] : label;

  @override
  String toString() => 'FlowSubgraph($id, узлов ${nodes.length}, вложенных ${subgraphs.length})';
}

/// Разобранный `flowchart`.
class FlowchartDiagram {
  const FlowchartDiagram({required this.direction, required this.nodes, required this.edges, required this.subgraphs});

  final FlowDirection direction;

  /// Узлы в порядке появления в тексте.
  ///
  /// Порядок значащий: с него начинается упорядочивание внутри слоя, и картинка
  /// от этого похожа на то, как автор её писал (`mermaid.md`, §7).
  final List<FlowNode> nodes;

  final List<FlowEdge> edges;

  /// Подграфы в порядке появления; вложенные — тоже здесь, плоским списком.
  final List<FlowSubgraph> subgraphs;

  @override
  String toString() => 'FlowchartDiagram(${direction.keyword}, узлов ${nodes.length}, рёбер ${edges.length})';
}
