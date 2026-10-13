import '../flowchart/flowchart_model.dart';
import '../mermaid_error.dart';
import '../text/lexer.dart';
import 'er_model.dart';

/// Разобрать `erDiagram`.
///
/// Чистый Dart, без Flutter. Ошибка — [MermaidError] с номером строки; молча
/// пропускается только оформление, тем же правилом, что во `flowchart`
/// (`docs/spec/mermaid.md`, §7а).
ErDiagram parseErDiagram(String source) {
  final lines = lexMermaid(source);
  if (lines.isEmpty) {
    throw const MermaidError(1, 'the diagram is empty');
  }

  final parser = _Parser();
  for (final line in lines.skip(1)) {
    parser.line(line);
  }

  return parser.done();
}

/// Имя сущности: буквы любого алфавита, цифры, `_`, а внутри — и дефис
/// (`LINE-ITEM`). На краях дефиса нет: иначе он слился бы с линией связи.
const String _name = r'(?:"[^"]+"|[\p{L}\p{N}_](?:[\p{L}\p{N}_\-]*[\p{L}\p{N}_])?)';

/// Кардинальность словами — вместо значков (`one or more to zero or many`).
const Map<String, ErCard> _cardWords = {
  'one or zero': ErCard.zeroOrOne,
  'zero or one': ErCard.zeroOrOne,
  'one or more': ErCard.oneOrMore,
  'one or many': ErCard.oneOrMore,
  'many(1)': ErCard.oneOrMore,
  '1+': ErCard.oneOrMore,
  'zero or more': ErCard.zeroOrMore,
  'zero or many': ErCard.zeroOrMore,
  'many(0)': ErCard.zeroOrMore,
  '0+': ErCard.zeroOrMore,
  'only one': ErCard.exactlyOne,
  '1': ErCard.exactlyOne,
};

/// Значки слева от линии.
const Map<String, ErCard> _leftCards = {
  '|o': ErCard.zeroOrOne,
  '||': ErCard.exactlyOne,
  '}o': ErCard.zeroOrMore,
  '}|': ErCard.oneOrMore,
};

/// Значки справа — зеркально.
const Map<String, ErCard> _rightCards = {
  'o|': ErCard.zeroOrOne,
  '||': ErCard.exactlyOne,
  'o{': ErCard.zeroOrMore,
  '|{': ErCard.oneOrMore,
};

final RegExp _symbolRelation = RegExp(
  '^($_name)\\s*(\\S{2})(--|\\.\\.)(\\S{2})\\s*($_name)\\s*(?::(.*))?\$',
  unicode: true,
);

final RegExp _wordRelation = RegExp(
  '^($_name)\\s+(${_cardWords.keys.map(RegExp.escape).join('|')})\\s+(to|optionally to)\\s+'
  '(${_cardWords.keys.map(RegExp.escape).join('|')})\\s+($_name)\\s*(?::(.*))?\$',
  unicode: true,
  caseSensitive: false,
);

/// Объявление сущности: имя, псевдоним, оформление `:::`, открытый или пустой
/// блок.
final RegExp _entity = RegExp(
  '^($_name)(?:\\[([^\\]]*)\\])?(?:\\s*:::[\\p{L}\\p{N}_\\-]+)?\\s*(\\{\\s*\\}|\\{)?\$',
  unicode: true,
);

/// Атрибут: тип, имя, ключи через запятую, комментарий в кавычках.
final RegExp _attribute = RegExp(
  r'^([^\s"]+)\s+([^\s"]+)((?:\s+(?:PK|FK|UK)(?:\s*,\s*(?:PK|FK|UK))*)?)(?:\s+"([^"]*)")?$',
  caseSensitive: false,
);

/// Сущность, пока её собирают: атрибуты приходят построчно, а псевдоним —
/// с любым упоминанием.
class _Entity {
  _Entity(this.id);

  final String id;
  String? label;
  final List<ErAttribute> attributes = [];
}

class _Parser {
  final Map<String, _Entity> _entities = {};

  /// Порядок первой встречи — с него начинается порядок в слое.
  final List<String> _order = [];

  final List<ErRelation> _relations = [];

  FlowDirection _direction = FlowDirection.topDown;

  /// Сущность, чей блок `{` сейчас открыт, и где он открыт.
  _Entity? _open;
  int _openedAt = 0;

  /// Строки, которые разбираются и не применяются: оформление.
  static const Set<String> _ignored = {'style', 'classdef', 'class'};

  void line(MermaidLine line) {
    final text = line.text;

    if (_open != null) {
      _insideBlock(line);

      return;
    }

    final word = text.split(RegExp(r'\s')).first.toLowerCase();
    if (_ignored.contains(word)) {
      return;
    }
    if (word == 'direction') {
      _direction = _directionOf(line);

      return;
    }
    if (text == '}') {
      throw MermaidError(line.number, 'this brace closes nothing');
    }

    if (_relation(line)) {
      return;
    }

    final entity = _entity.firstMatch(text);
    if (entity != null) {
      final declared = _declare(entity.group(1)!, alias: entity.group(2));
      final brace = entity.group(3);
      if (brace == '{') {
        _open = declared;
        _openedAt = line.number;
      }

      return;
    }

    if (text.contains('--') || text.contains('..')) {
      throw MermaidError(line.number, 'this relationship does not say its cardinality');
    }

    throw MermaidError(line.number, 'do not understand this line');
  }

  ErDiagram done() {
    if (_open != null) {
      throw MermaidError(_openedAt, 'this block is never closed');
    }

    return ErDiagram(
      direction: _direction,
      entities: [
        for (final id in _order)
          ErEntity(id: id, label: _entities[id]!.label ?? id, attributes: List.unmodifiable(_entities[id]!.attributes)),
      ],
      relations: List.unmodifiable(_relations),
    );
  }

  void _insideBlock(MermaidLine line) {
    if (line.text == '}') {
      _open = null;

      return;
    }

    final match = _attribute.firstMatch(line.text);
    if (match == null) {
      throw MermaidError(line.number, 'this line does not say what the attribute is');
    }

    final keys = [
      for (final key in (match.group(3) ?? '').split(','))
        if (key.trim().isNotEmpty) ErKey.values.firstWhere((value) => value.keyword == key.trim().toUpperCase()),
    ];

    _open!.attributes.add(
      ErAttribute(type: match.group(1)!, name: match.group(2)!, keys: keys, comment: match.group(4) ?? ''),
    );
  }

  /// Связь — значками или словами. false — это не связь вовсе.
  bool _relation(MermaidLine line) {
    final symbols = _symbolRelation.firstMatch(line.text);
    if (symbols != null) {
      final left = _leftCards[symbols.group(2)];
      final right = _rightCards[symbols.group(4)];
      if (left == null || right == null) {
        throw MermaidError(line.number, 'this relationship does not say its cardinality');
      }
      _relate(
        line,
        from: symbols.group(1)!,
        to: symbols.group(5)!,
        fromCard: left,
        toCard: right,
        identifying: symbols.group(3) == '--',
        label: symbols.group(6),
      );

      return true;
    }

    final words = _wordRelation.firstMatch(line.text);
    if (words != null) {
      _relate(
        line,
        from: words.group(1)!,
        to: words.group(5)!,
        fromCard: _cardWords[words.group(2)!.toLowerCase()]!,
        toCard: _cardWords[words.group(4)!.toLowerCase()]!,
        identifying: words.group(3)!.toLowerCase() == 'to',
        label: words.group(6),
      );

      return true;
    }

    return false;
  }

  void _relate(
    MermaidLine line, {
    required String from,
    required String to,
    required ErCard fromCard,
    required ErCard toCard,
    required bool identifying,
    required String? label,
  }) {
    if (label == null) {
      throw MermaidError(line.number, 'a relationship needs a colon and its label');
    }

    _relations.add(
      ErRelation(
        from: _declare(from).id,
        to: _declare(to).id,
        fromCard: fromCard,
        toCard: toCard,
        identifying: identifying,
        label: _unquote(label.trim()),
      ),
    );
  }

  /// Завести сущность при первой встрече; псевдоним уточняет подпись.
  _Entity _declare(String name, {String? alias}) {
    final id = _unquote(name);
    final entity = _entities.putIfAbsent(id, () {
      _order.add(id);

      return _Entity(id);
    });
    if (alias != null && alias.trim().isNotEmpty) {
      entity.label = _unquote(alias.trim());
    }

    return entity;
  }

  static String _unquote(String text) =>
      text.length >= 2 && text.startsWith('"') && text.endsWith('"') ? text.substring(1, text.length - 1) : text;

  static FlowDirection _directionOf(MermaidLine line) {
    final word = line.text.substring('direction'.length).trim().toUpperCase();

    return switch (word) {
      'TB' || 'TD' => FlowDirection.topDown,
      'BT' => FlowDirection.bottomUp,
      'LR' => FlowDirection.leftRight,
      'RL' => FlowDirection.rightLeft,
      _ => throw MermaidError(line.number, 'this is not a direction'),
    };
  }
}
