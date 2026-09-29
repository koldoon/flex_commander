import 'dart:math' as math;

import '../mermaid_error.dart';
import '../text/lexer.dart';
import 'flowchart_model.dart';

/// Разобрать `flowchart` (он же `graph`).
///
/// Чистый Dart: ни одного обращения к Flutter — разбор проверяется обычными
/// тестами, без биндинга (`docs/spec/mermaid.md`, §4).
///
/// Ошибка — [MermaidError] с номером строки. Молча пропускается только
/// оформление: цвета в приложении назначает тема, и отказывать из-за строки,
/// которая к смыслу диаграммы не относится, значило бы превратить законную
/// диаграмму в текст (§7).
FlowchartDiagram parseFlowchart(String source) {
  final lines = lexMermaid(source);
  if (lines.isEmpty) {
    throw const MermaidError(1, 'the diagram is empty');
  }

  final parser = _Parser(_directionOf(lines.first));
  for (final line in lines.skip(1)) {
    parser.line(line);
  }

  return parser.done(openedAt: lines.first.number);
}

/// Направление из объявления: `flowchart LR`. Не сказано — сверху вниз.
FlowDirection _directionOf(MermaidLine line) {
  final cut = line.text.indexOf(RegExp(r'\s'));
  if (cut < 0) {
    return FlowDirection.topDown;
  }

  final word = line.text.substring(cut).trim().toUpperCase();

  return switch (word) {
    '' || 'TD' || 'TB' => FlowDirection.topDown,
    'BT' => FlowDirection.bottomUp,
    'LR' => FlowDirection.leftRight,
    'RL' => FlowDirection.rightLeft,
    _ => throw MermaidError(line.number, 'this is not a direction'),
  };
}

/// Открытый подграф: собирается, пока не встретится `end`.
class _OpenSubgraph {
  _OpenSubgraph({required this.id, required this.label, required this.openedAt});

  final String id;
  final List<String> label;

  /// Где открыт: на эту строку укажет отказ, если его не закроют.
  final int openedAt;

  final List<String> nodes = [];
  final List<String> subgraphs = [];
}

/// Кусок строки между рёбрами: один узел или несколько через `&`.
class _Chunk {
  const _Chunk(this.text);

  final String text;
}

/// Разобранное ребро — и сколько знаков оно заняло в строке.
class _Edge {
  const _Edge({
    required this.length,
    required this.line,
    required this.head,
    required this.tail,
    required this.span,
    this.label = const [],
  });

  final int length;
  final FlowLine line;
  final FlowEnd head;
  final FlowEnd tail;
  final int span;
  final List<String> label;
}

class _Parser {
  _Parser(this._direction);

  final FlowDirection _direction;

  /// Узлы в порядке появления: по нему начинается упорядочивание внутри слоя.
  final Map<String, FlowNode> _nodes = {};

  final List<FlowEdge> _edges = [];
  final List<FlowSubgraph> _subgraphs = [];

  /// Открытые подграфы; последний — самый глубокий.
  final List<_OpenSubgraph> _open = [];

  /// Строки, которые разбираются и не применяются: оформление.
  static const Set<String> _ignored = {'style', 'classdef', 'class', 'linkstyle', 'click'};

  void line(MermaidLine line) {
    final word = _word(line.text).toLowerCase();

    if (_ignored.contains(word)) {
      return;
    }

    switch (word) {
      case 'subgraph':
        _openSubgraph(line);

        return;

      case 'end':
        _closeSubgraph(line);

        return;

      case 'direction':
        // Не пропускаем молча: пропустить — значит нарисовать подграф в чужом
        // направлении и не сказать об этом (§7).
        throw MermaidError(line.number, 'a direction inside a subgraph is not drawn yet');
    }

    _statement(line);
  }

  FlowchartDiagram done({required int openedAt}) {
    if (_open.isNotEmpty) {
      throw MermaidError(_open.last.openedAt, 'this block is never closed');
    }

    return FlowchartDiagram(direction: _direction, nodes: _nodes.values.toList(), edges: _edges, subgraphs: _subgraphs);
  }

  // --- подграфы ---

  void _openSubgraph(MermaidLine line) {
    final rest = line.text.substring('subgraph'.length).trim();
    if (rest.isEmpty) {
      throw MermaidError(line.number, 'this line does not say what the subgraph is');
    }

    final titled = RegExp(r'^(\S+)\s*\[(.*)\]$').firstMatch(rest);
    final id = titled == null ? rest : titled.group(1)!;
    final label = titled == null ? const <String>[] : _labelLines(titled.group(2)!);

    _open.add(_OpenSubgraph(id: id, label: label, openedAt: line.number));
  }

  void _closeSubgraph(MermaidLine line) {
    if (_open.isEmpty) {
      throw MermaidError(line.number, 'this end closes nothing');
    }

    final closed = _open.removeLast();
    _subgraphs.add(FlowSubgraph(id: closed.id, label: closed.label, nodes: closed.nodes, subgraphs: closed.subgraphs));

    if (_open.isNotEmpty) {
      _open.last.subgraphs.add(closed.id);
    }
  }

  // --- утверждения: цепочки узлов и рёбер ---

  void _statement(MermaidLine line) {
    final parts = _scan(line);

    // Чередование обязано начинаться и кончаться узлами: `A --> B --> C`.
    var previous = _chunkNodes(line, parts.first as _Chunk);

    for (var i = 1; i < parts.length; i += 2) {
      final edge = parts[i] as _Edge;
      final next = _chunkNodes(line, parts[i + 1] as _Chunk);

      // Пучок: каждый слева с каждым справа.
      for (final from in previous) {
        for (final to in next) {
          _edges.add(
            FlowEdge(
              from: from,
              to: to,
              line: edge.line,
              head: edge.head,
              tail: edge.tail,
              label: edge.label,
              span: edge.span,
            ),
          );
        }
      }
      previous = next;
    }
  }

  /// Разложить строку на куски и рёбра между ними.
  ///
  /// Скобки считаются: подпись узла законно содержит и `-`, и `=`, и `>`, и
  /// принять их за ребро значило бы разорвать `A[раз-два] --> B` посередине
  /// подписи.
  List<Object> _scan(MermaidLine line) {
    final text = line.text;
    final parts = <Object>[];
    final buffer = StringBuffer();
    var depth = 0;
    var i = 0;

    while (i < text.length) {
      if (depth == 0) {
        final edge = _edgeAt(line, i);
        if (edge != null) {
          parts.add(_Chunk(buffer.toString()));
          buffer.clear();
          parts.add(edge);
          i += edge.length;
          continue;
        }
      }

      final ch = text[i];
      if (ch == '[' || ch == '(' || ch == '{') {
        depth++;
      } else if (ch == ']' || ch == ')' || ch == '}') {
        depth = math.max(0, depth - 1);
      }
      buffer.write(ch);
      i++;
    }
    parts.add(_Chunk(buffer.toString()));

    return parts;
  }

  /// Ребро, начинающееся ровно здесь; null — не ребро.
  _Edge? _edgeAt(MermaidLine line, int at) {
    final text = line.text;
    final ch = text[at];
    if (ch != '-' && ch != '=' && ch != '<' && ch != '~' && ch != 'o' && ch != 'x') {
      return null;
    }

    // `o--o` и `x--x` опознаём только отдельным словом: иначе `foo-->B`
    // разорвалось бы по букве `o` в имени.
    final standalone = at == 0 || text[at - 1] == ' ' || text[at - 1] == '\t';

    if (_invisible.matchAsPrefix(text, at) != null) {
      throw MermaidError(line.number, 'invisible links are not drawn yet');
    }
    if (standalone && _bothEnds.matchAsPrefix(text, at) != null) {
      throw MermaidError(line.number, 'a link with heads at both ends is not drawn yet');
    }

    // Подпись внутри линии — только у стрелки с наконечником: без него её не
    // отличить от цепочки `A --- B --- C` (§7).
    final solidLabel = _solidLabel.matchAsPrefix(text, at);
    if (solidLabel != null) {
      return _labelled(line, solidLabel, FlowLine.solid, at);
    }
    final thickLabel = _thickLabel.matchAsPrefix(text, at);
    if (thickLabel != null) {
      return _labelled(line, thickLabel, FlowLine.thick, at);
    }
    final dottedLabel = _dottedLabel.matchAsPrefix(text, at);
    if (dottedLabel != null) {
      return _labelled(line, dottedLabel, FlowLine.dotted, at);
    }

    // Пунктир раньше сплошной: `-.-` начинается с того же дефиса.
    final dotted = _dotted.matchAsPrefix(text, at);
    if (dotted != null) {
      return _edge(line, dotted, at, kind: FlowLine.dotted, head: _end(dotted.group(2)), span: dotted.group(1)!.length);
    }
    final thick = _thick.matchAsPrefix(text, at);
    if (thick != null) {
      return _edge(
        line,
        thick,
        at,
        kind: FlowLine.thick,
        head: _end(thick.group(3)),
        tail: thick.group(1) == '<' ? FlowEnd.arrow : FlowEnd.none,
        span: _span(thick.group(2)! + (thick.group(3) ?? '')),
      );
    }
    final solid = _solid.matchAsPrefix(text, at);
    if (solid != null) {
      return _edge(
        line,
        solid,
        at,
        kind: FlowLine.solid,
        head: _end(solid.group(3)),
        tail: solid.group(1) == '<' ? FlowEnd.arrow : FlowEnd.none,
        span: _span(solid.group(2)! + (solid.group(3) ?? '')),
      );
    }

    return null;
  }

  _Edge _labelled(MermaidLine line, Match match, FlowLine kind, int at) {
    final closing = match.group(2)!;
    final head = match.group(3) ?? '';

    return _edge(
      line,
      match,
      at,
      kind: kind,
      head: _end(match.group(3)),
      // Длину задаёт закрывающая часть: открывающая у подписи всегда в два
      // знака. У пунктира считаем её дефисы — точки там разделитель.
      span: kind == FlowLine.dotted ? closing.replaceAll('.', '').length : _span(closing + head),
      label: _labelLines(match.group(1)!),
    );
  }

  /// Собрать ребро: длина в знаках, подпись из `|…|`, если она там.
  _Edge _edge(
    MermaidLine line,
    Match match,
    int at, {
    required FlowLine kind,
    required FlowEnd head,
    FlowEnd tail = FlowEnd.none,
    required int span,
    List<String> label = const [],
  }) {
    final pipe = _pipeAt(line.text, at + match.group(0)!.length);

    return _Edge(
      length: match.group(0)!.length + (pipe?.group(0)?.length ?? 0),
      line: kind,
      head: head,
      tail: tail,
      span: math.max(1, span),
      label: pipe == null ? label : _labelLines(pipe.group(1)!),
    );
  }

  /// Подпись после ребра: `--> |текст|`.
  Match? _pipeAt(String text, int at) => at >= text.length ? null : _pipe.matchAsPrefix(text, at);

  // --- узлы ---

  /// Имена узлов куска: `A[раз] & B(два)` — два.
  List<String> _chunkNodes(MermaidLine line, _Chunk chunk) {
    final names = <String>[];
    for (final piece in _splitAmp(chunk.text)) {
      names.add(_node(line, piece));
    }
    if (names.isEmpty) {
      throw MermaidError(line.number, 'a link needs both of its ends');
    }

    return names;
  }

  /// Разбить по `&` на глубине скобок ноль.
  List<String> _splitAmp(String text) {
    final pieces = <String>[];
    final buffer = StringBuffer();
    var depth = 0;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '[' || ch == '(' || ch == '{') {
        depth++;
      } else if (ch == ']' || ch == ')' || ch == '}') {
        depth = math.max(0, depth - 1);
      }
      if (ch == '&' && depth == 0) {
        pieces.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(ch);
    }
    pieces.add(buffer.toString());

    return pieces;
  }

  /// Завести узел по его записи и вернуть имя.
  String _node(MermaidLine line, String piece) {
    var text = piece.trim().replaceFirst(_className, '');
    if (text.isEmpty) {
      throw MermaidError(line.number, 'a link needs both of its ends');
    }

    final at = text.indexOf(RegExp(r'[\[({>]'));
    if (at < 0) {
      _use(line, text, const [], null);

      return text;
    }

    final id = text.substring(0, at).trim();
    if (id.isEmpty) {
      throw MermaidError(line.number, 'this line does not say what the node is');
    }

    final body = text.substring(at);
    for (final shape in _shapes) {
      if (body.length >= shape.open.length + shape.close.length &&
          body.startsWith(shape.open) &&
          body.endsWith(shape.close)) {
        final inside = body.substring(shape.open.length, body.length - shape.close.length);
        _use(line, id, _labelLines(inside), shape.shape);

        return id;
      }
    }

    throw MermaidError(line.number, 'do not understand this line');
  }

  /// Узел встретился: завести или уточнить.
  ///
  /// Форму и подпись задаёт то объявление, где они есть; ссылка одним именем
  /// ничего не стирает — как псевдоним участника в §6.
  void _use(MermaidLine line, String id, List<String> label, FlowShape? shape) {
    final known = _nodes[id];
    final fresh = known == null;

    _nodes[id] = FlowNode(
      id: id,
      label: label.isNotEmpty ? label : (known?.label ?? const []),
      shape: shape ?? known?.shape ?? FlowShape.rect,
    );

    // В подграф узел попадает по первой встрече — в тот, что открыт сейчас.
    if (fresh && _open.isNotEmpty) {
      _open.last.nodes.add(id);
    }
  }

  // --- мелочи ---

  static String _word(String text) {
    final cut = text.indexOf(RegExp(r'\s'));

    return cut < 0 ? text : text.substring(0, cut);
  }

  static List<String> _labelLines(String text) {
    var body = text.trim();
    if (body.length >= 2 && body.startsWith('"') && body.endsWith('"')) {
      body = body.substring(1, body.length - 1).trim();
    }
    if (body.isEmpty) {
      return const [];
    }

    return [for (final part in mermaidLabelLines(body)) part];
  }

  static FlowEnd _end(String? mark) => switch (mark) {
    '>' => FlowEnd.arrow,
    'o' => FlowEnd.circle,
    'x' => FlowEnd.cross,
    _ => FlowEnd.none,
  };

  /// Длина ребра по его записи: короче короткого не бывает.
  ///
  /// Считается вся запись вместе с наконечником: у стрелки короткое — `-->`,
  /// у линии без наконечника — `---`, и то и другое три знака.
  static int _span(String token) => math.max(1, token.length - 2);

  /// Имя класса в конце записи узла. `\w` здесь не годится: имена пишут и
  /// кириллицей, а он её не берёт.
  static final RegExp _className = RegExp(r':::\S+\s*$');
  static final RegExp _invisible = RegExp(r'~{3,}');
  static final RegExp _bothEnds = RegExp(r'[ox](?:-{2,}|={2,})[ox]');
  static final RegExp _pipe = RegExp(r'\s*\|([^|]*)\|');

  /// Подпись внутри линии: открывающая часть — **ровно два знака**.
  ///
  /// Так же различает и сам mermaid, и иначе не отличить подпись от цепочки:
  /// в `A --- B --> C` жадное начало съело бы `--- B -->` и объявило бы «B»
  /// подписью ребра из `A` в `C`. Длину ребра задаёт закрывающая часть.
  static final RegExp _solidLabel = RegExp(r'--\s+(.+?)\s+(-{2,})([>ox]?)');
  static final RegExp _thickLabel = RegExp(r'==\s+(.+?)\s+(={2,})([>ox]?)');
  static final RegExp _dottedLabel = RegExp(r'-\.\s+(.+?)\s+(\.-+)([>ox]?)');

  static final RegExp _dotted = RegExp(r'-(\.+)-([>ox]?)');
  static final RegExp _solid = RegExp(r'(<)?(-{2,})([>ox]?)');
  static final RegExp _thick = RegExp(r'(<)?(={2,})([>ox]?)');

  /// Формы по скобкам. Порядок значащий: длинные пары раньше коротких, иначе
  /// `[[текст]]` опознается как `[` с квадратными скобками в подписи.
  static const List<({String open, String close, FlowShape shape})> _shapes = [
    (open: '([', close: '])', shape: FlowShape.stadium),
    (open: '[[', close: ']]', shape: FlowShape.subroutine),
    (open: '[(', close: ')]', shape: FlowShape.cylinder),
    (open: '[/', close: r'\]', shape: FlowShape.trapezoid),
    (open: r'[\', close: '/]', shape: FlowShape.trapezoidAlt),
    (open: '[/', close: '/]', shape: FlowShape.parallelogram),
    (open: r'[\', close: r'\]', shape: FlowShape.parallelogramAlt),
    (open: '((', close: '))', shape: FlowShape.circle),
    (open: '{{', close: '}}', shape: FlowShape.hexagon),
    (open: '[', close: ']', shape: FlowShape.rect),
    (open: '(', close: ')', shape: FlowShape.rounded),
    (open: '{', close: '}', shape: FlowShape.rhombus),
    (open: '>', close: ']', shape: FlowShape.flag),
  ];
}
