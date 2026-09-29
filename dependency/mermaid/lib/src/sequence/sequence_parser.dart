import '../mermaid_error.dart';
import '../text/lexer.dart';
import 'sequence_model.dart';

/// Разобрать `sequenceDiagram`.
///
/// Чистый Dart: ни одного обращения к Flutter — разбор проверяется обычными
/// тестами, без биндинга (`docs/spec/mermaid.md`, §4).
///
/// Ошибка — [MermaidError] с номером строки. Молча пропускать непонятое нельзя:
/// диаграмма нарисуется не та, а человек об этом не узнает.
SequenceDiagram parseSequenceDiagram(String source) {
  final lines = lexMermaid(source);
  if (lines.isEmpty) {
    throw const MermaidError(1, 'the diagram is empty');
  }

  final parser = _Parser();

  // Первая значащая строка объявляет вид — её уже прочитали снаружи.
  return parser.run(lines.skip(1).toList(), openedAt: lines.first.number);
}

/// Рамка разбора: корень или открытый блок.
class _Frame {
  _Frame({this.kind, required this.openedAt, this.label = ''});

  /// null — корень диаграммы.
  final BlockKind? kind;

  /// Где открыт: на эту строку укажет отказ, если блок не закроют.
  final int openedAt;

  /// Ярлык текущей ветви.
  String label;

  final List<SequenceStep> steps = [];
  final List<SequenceSection> sections = [];
}

class _Parser {
  final List<SequenceParticipant> _participants = [];
  final Map<String, int> _index = {};
  bool _autonumber = false;

  SequenceDiagram run(List<MermaidLine> lines, {required int openedAt}) {
    final stack = <_Frame>[_Frame(openedAt: openedAt)];

    for (final line in lines) {
      _line(line, stack);
    }

    if (stack.length > 1) {
      throw MermaidError(stack.last.openedAt, 'this block is never closed');
    }

    return SequenceDiagram(participants: _participants, steps: stack.single.steps, autonumber: _autonumber);
  }

  void _line(MermaidLine line, List<_Frame> stack) {
    final text = line.text;
    final word = _word(text);

    switch (word) {
      case 'autonumber':
        _autonumber = true;

        return;

      case 'participant':
      case 'actor':
        _declare(line, actor: word == 'actor');

        return;

      case 'activate':
      case 'deactivate':
        final name = text.substring(word.length).trim();
        if (name.isEmpty) {
          throw MermaidError(line.number, 'this line does not say whose activation it is');
        }
        stack.last.steps.add(SequenceActivation(participant: _id(name), start: word == 'activate'));

        return;

      case 'note':
        stack.last.steps.add(_note(line));

        return;

      case 'end':
        _close(line, stack);

        return;
    }

    if (_opener(word) case final kind?) {
      stack.add(_Frame(kind: kind, openedAt: line.number, label: text.substring(word.length).trim()));

      return;
    }

    if (_separator(word)) {
      _section(line, stack, text.substring(word.length).trim());

      return;
    }

    if (_message(line) case final message?) {
      stack.last.steps.add(message);

      return;
    }

    throw MermaidError(line.number, 'do not understand this line');
  }

  /// Первое слово строки, в нижнем регистре.
  String _word(String text) {
    final cut = text.indexOf(RegExp(r'\s'));
    final head = cut < 0 ? text : text.substring(0, cut);

    return head.toLowerCase();
  }

  /// `participant X as Y` — объявление со своим порядком следования.
  void _declare(MermaidLine line, {required bool actor}) {
    final rest = line.text.substring(actor ? 'actor'.length : 'participant'.length).trim();
    if (rest.isEmpty) {
      throw MermaidError(line.number, 'this line does not say who the participant is');
    }

    final parts = rest.split(RegExp(r'\s+as\s+', caseSensitive: false));
    final id = parts.first.trim();
    final label = parts.length > 1 ? parts.sublist(1).join(' as ').trim() : id;

    final at = _index[id];
    if (at != null) {
      // Объявили второй раз — уточняем подпись, а не заводим второй столбец.
      _participants[at] = SequenceParticipant(
        id: id,
        label: label,
        shape: actor ? ParticipantShape.person : ParticipantShape.box,
      );

      return;
    }

    _index[id] = _participants.length;
    _participants.add(
      SequenceParticipant(id: id, label: label, shape: actor ? ParticipantShape.person : ParticipantShape.box),
    );
  }

  /// Имя участника: встреченный в сообщении заводится на лету, как у mermaid.
  String _id(String name) {
    final id = name.trim();
    if (!_index.containsKey(id)) {
      _index[id] = _participants.length;
      _participants.add(SequenceParticipant(id: id, label: id));
    }

    return id;
  }

  /// `Note over A,B: текст`.
  SequenceNote _note(MermaidLine line) {
    final colon = line.text.indexOf(':');
    if (colon < 0) {
      throw MermaidError(line.number, 'a note needs a colon and its text');
    }

    final head = line.text.substring(0, colon).trim();
    final label = mermaidLabelLines(line.text.substring(colon + 1).trim());

    final match = RegExp(r'^note\s+(left of|right of|over)\s+(.+)$', caseSensitive: false).firstMatch(head);
    if (match == null) {
      throw MermaidError(line.number, 'a note must say left of, right of or over');
    }

    final placement = switch (match.group(1)!.toLowerCase()) {
      'left of' => NotePlacement.leftOf,
      'right of' => NotePlacement.rightOf,
      _ => NotePlacement.over,
    };
    final of = [for (final name in match.group(2)!.split(',')) _id(name)];

    return SequenceNote(placement: placement, of: of, label: label);
  }

  /// Слово открывает блок?
  BlockKind? _opener(String word) => switch (word) {
    'alt' => BlockKind.alt,
    'opt' => BlockKind.opt,
    'loop' => BlockKind.loop,
    'par' => BlockKind.par,
    'critical' => BlockKind.critical,
    'break' => BlockKind.breakBlock,
    _ => null,
  };

  /// Слово делит блок на ветви?
  bool _separator(String word) => word == 'else' || word == 'and' || word == 'option';

  void _section(MermaidLine line, List<_Frame> stack, String label) {
    if (stack.length == 1) {
      throw MermaidError(line.number, 'this line divides a block, but no block is open');
    }
    final frame = stack.last;
    frame.sections.add(SequenceSection(label: frame.label, steps: [...frame.steps]));
    frame.steps.clear();
    frame.label = label;
  }

  void _close(MermaidLine line, List<_Frame> stack) {
    if (stack.length == 1) {
      throw MermaidError(line.number, 'this end closes nothing');
    }

    final frame = stack.removeLast();
    frame.sections.add(SequenceSection(label: frame.label, steps: [...frame.steps]));
    stack.last.steps.add(SequenceBlock(kind: frame.kind!, sections: frame.sections));
  }

  /// `A->>+B: текст` — сообщение со стрелкой и, может быть, отметкой активности.
  SequenceMessage? _message(MermaidLine line) {
    final colon = line.text.indexOf(':');
    final head = colon < 0 ? line.text : line.text.substring(0, colon);
    final label = colon < 0 ? const <String>[] : mermaidLabelLines(line.text.substring(colon + 1).trim());

    final found = _findArrow(head);
    if (found == null) {
      return null;
    }

    final (at, token, arrow) = found;
    final from = head.substring(0, at).trim();
    var tail = head.substring(at + token.length).trim();

    var activates = false;
    var deactivates = false;
    if (tail.startsWith('+')) {
      activates = true;
      tail = tail.substring(1).trim();
    } else if (tail.startsWith('-')) {
      deactivates = true;
      tail = tail.substring(1).trim();
    }

    if (from.isEmpty || tail.isEmpty) {
      throw MermaidError(line.number, 'a message needs both sides of the arrow');
    }

    return SequenceMessage(
      from: _id(from),
      to: _id(tail),
      arrow: arrow,
      label: label,
      activates: activates,
      deactivates: deactivates,
    );
  }

  /// Найти стрелку: самую левую, а при равенстве — самую длинную.
  ///
  /// Длинную вперёд короткой обязательно: иначе `-->>` разобралось бы как `-`
  /// плюс мусор, а `A-->>-B` потеряло бы отметку закрытия.
  (int, String, SequenceArrow)? _findArrow(String head) {
    for (var i = 0; i < head.length; i++) {
      for (final token in _arrowTokens) {
        if (head.startsWith(token, i)) {
          return (i, token, _arrows[token]!);
        }
      }
    }

    return null;
  }
}

/// Стрелки, от длинной к короткой.
const List<String> _arrowTokens = ['<<-->>', '<<->>', '-->>', '--x', '--)', '-->', '->>', '-x', '-)', '->'];

const Map<String, SequenceArrow> _arrows = {
  '<<-->>': SequenceArrow(head: ArrowHead.arrow, dotted: true),
  '<<->>': SequenceArrow(head: ArrowHead.arrow, dotted: false),
  '-->>': SequenceArrow(head: ArrowHead.arrow, dotted: true),
  '->>': SequenceArrow(head: ArrowHead.arrow, dotted: false),
  '--x': SequenceArrow(head: ArrowHead.cross, dotted: true),
  '-x': SequenceArrow(head: ArrowHead.cross, dotted: false),
  '--)': SequenceArrow(head: ArrowHead.open, dotted: true),
  '-)': SequenceArrow(head: ArrowHead.open, dotted: false),
  '-->': SequenceArrow(head: ArrowHead.none, dotted: true),
  '->': SequenceArrow(head: ArrowHead.none, dotted: false),
};
