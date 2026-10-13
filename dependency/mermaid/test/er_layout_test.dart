import 'dart:ui';

import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Замер с постоянной шириной знака: координаты становятся точными числами.
class _FakeMeasure implements DiagramTextMeasure {
  const _FakeMeasure();

  @override
  DiagramTextRun run(String text, DiagramTextRole role, {double maxWidth = double.infinity}) =>
      _FakeRun(text, Size(text.length * 7.0, 16));
}

class _FakeRun implements DiagramTextRun {
  const _FakeRun(this.text, this.size);

  final String text;

  @override
  final Size size;

  @override
  void paint(Canvas canvas, Offset at) {}
}

/// Раскладка `erDiagram` (`docs/spec/mermaid.md`, §7а): проверяются свойства, а
/// не координаты.
void main() {
  const measure = _FakeMeasure();

  DiagramLayout layout(String body) => layoutErDiagram(parseErDiagram('erDiagram\n$body'), measure);

  /// Рамки таблиц — в порядке сущностей: у каждой таблицы своя залитая рамка.
  List<Rect> tablesOf(DiagramLayout l) => [
    for (final box in l.shapes.whereType<DiagramBox>())
      if (box.ink == DiagramInk.fill) box.rect,
  ];

  const er = {DiagramHead.exactlyOne, DiagramHead.zeroOrOne, DiagramHead.oneOrMore, DiagramHead.zeroOrMore};
  List<DiagramPath> relationsOf(DiagramLayout l) => [
    for (final path in l.shapes.whereType<DiagramPath>())
      if (er.contains(path.head)) path,
  ];

  DiagramLabel labelOf(DiagramLayout l, String text) =>
      l.shapes.whereType<DiagramLabel>().firstWhere((label) => (label.run as _FakeRun).text == text);

  /// Точка лежит на рамке: внутри неё (с допуском) и вплотную к одной из сторон.
  bool onBorder(Rect rect, Offset point) {
    if (!rect.inflate(0.5).contains(point)) {
      return false;
    }
    final distances = [
      (point.dx - rect.left).abs(),
      (point.dx - rect.right).abs(),
      (point.dy - rect.top).abs(),
      (point.dy - rect.bottom).abs(),
    ];

    return distances.reduce((a, b) => a < b ? a : b) < 0.5;
  }

  const shop = '''
CUSTOMER ||--o{ ORDER : places
ORDER ||--|{ LINE-ITEM : contains
CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
CUSTOMER {
  string name
  string custNumber PK "the number"
  string sector
}
ORDER {
  int orderNumber PK
  string deliveryAddress FK, UK
}
''';

  test('таблица вмещает шапку и все строки атрибутов', () {
    final l = layout('CUSTOMER {\n  string name\n  int id PK "key"\n  string sector\n}');
    final table = tablesOf(l).single;

    for (final text in ['CUSTOMER', 'string', 'name', 'int', 'id', 'PK', 'key', 'sector']) {
      final label = labelOf(l, text);
      final rect = label.at & label.run.size;
      expect(
        table.inflate(0.01).contains(rect.topLeft) && table.inflate(0.01).contains(rect.bottomRight),
        isTrue,
        reason: text,
      );
    }

    // Строки идут сверху вниз, без наложения.
    final ys = [
      for (final text in ['name', 'id', 'sector']) labelOf(l, text).at.dy,
    ];
    expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
    expect(ys[1] - ys[0], greaterThanOrEqualTo(16));
  });

  test('колонки выровнены: одна колонка — одна левая граница', () {
    final l = layout('A {\n  int id PK\n  varchar(255) longer_name FK\n}');

    expect(labelOf(l, 'id').at.dx, labelOf(l, 'longer_name').at.dx);
    expect(labelOf(l, 'PK').at.dx, labelOf(l, 'FK').at.dx);
    // Колонка имени начинается правее самого длинного типа.
    expect(labelOf(l, 'id').at.dx, greaterThanOrEqualTo(labelOf(l, 'varchar(255)').at.dx + 'varchar(255)'.length * 7));
  });

  test('пустая колонка места не занимает', () {
    final plain = tablesOf(layout('A {\n  int id\n}')).single;
    final commented = tablesOf(layout('A {\n  int id "some comment"\n}')).single;

    expect(commented.width, greaterThan(plain.width));
  });

  test('сущность без атрибутов — одна шапка', () {
    final l = layout('A ||--o{ B : x');
    final plates = l.shapes.whereType<DiagramBox>().where((box) => box.ink == DiagramInk.plate).toList();

    for (var i = 0; i < 2; i++) {
      expect(tablesOf(l)[i].height, plates[i].rect.height);
    }
  });

  test('таблицы не налезают друг на друга', () {
    final tables = tablesOf(layout(shop));

    expect(tables, hasLength(4));
    for (var i = 0; i < tables.length; i++) {
      for (var j = i + 1; j < tables.length; j++) {
        expect(tables[i].overlaps(tables[j]), isFalse, reason: 'таблицы $i и $j');
      }
    }
  });

  test('связь: концы на рамках своих сущностей, знаки с нужных сторон', () {
    final l = layout('CUSTOMER ||--o{ ORDER : places');
    final tables = tablesOf(l);
    final relation = relationsOf(l).single;

    expect(onBorder(tables[0], relation.points.first), isTrue, reason: 'начало — на CUSTOMER');
    expect(onBorder(tables[1], relation.points.last), isTrue, reason: 'конец — на ORDER');
    expect(relation.tail, DiagramHead.exactlyOne);
    expect(relation.head, DiagramHead.zeroOrMore);
    expect(relation.dashed, isFalse);
  });

  test('каждая кардинальность — свой знак', () {
    const cases = {
      '|o--o|': (DiagramHead.zeroOrOne, DiagramHead.zeroOrOne),
      '||--||': (DiagramHead.exactlyOne, DiagramHead.exactlyOne),
      '}o--o{': (DiagramHead.zeroOrMore, DiagramHead.zeroOrMore),
      '}|--|{': (DiagramHead.oneOrMore, DiagramHead.oneOrMore),
    };

    for (final entry in cases.entries) {
      final relation = relationsOf(layout('A ${entry.key} B : x')).single;
      expect((relation.tail, relation.head), entry.value, reason: entry.key);
    }
  });

  test('`..` — пунктир', () {
    expect(relationsOf(layout('A ||..o{ B : x')).single.dashed, isTrue);
  });

  test('подпись связи — на подложке', () {
    expect(labelOf(layout('A ||--o{ B : places'), 'places').backdrop, isTrue);
  });

  test('подписи не налезают ни друг на друга, ни на таблицы', () {
    // Из одной таблицы две связи вниз: на одной высоте их подписи слипались
    // в одну строку — так это и нашлось на снимке.
    final l = layout('ORDER ||--|{ LINE-ITEM : contains\nORDER |o--o| INVOICE : "billed by"\n$shop');
    final tables = tablesOf(l);
    final labels = [
      for (final label in l.shapes.whereType<DiagramLabel>())
        if (label.backdrop) label.at & label.run.size,
    ];

    expect(labels, hasLength(5));
    for (var i = 0; i < labels.length; i++) {
      for (var j = i + 1; j < labels.length; j++) {
        // Не просто не пересекаются — между ними зазор: вплотную две подписи
        // читаются одной строкой.
        expect(labels[i].inflate(4).overlaps(labels[j]), isFalse, reason: 'подписи $i и $j');
      }
      for (final table in tables) {
        expect(labels[i].overlaps(table), isFalse, reason: 'подпись $i и таблица');
      }
    }
  });

  test('связи сглажены и выходят из рамки перпендикулярно её стороне', () {
    final l = layout(shop);
    final tables = tablesOf(l);

    for (final relation in relationsOf(l)) {
      expect(relation.smooth, isTrue);
      for (final (end, next) in [
        (relation.points.first, relation.points[1]),
        (relation.points.last, relation.points[relation.points.length - 2]),
      ]) {
        final table = tables.firstWhere((rect) => onBorder(rect, end));
        final step = next - end;
        final onTopOrBottom = (end.dy - table.top).abs() < 0.5 || (end.dy - table.bottom).abs() < 0.5;
        // Сверху или снизу — уходит по вертикали, сбоку — по горизонтали.
        expect(onTopOrBottom ? step.dx.abs() : step.dy.abs(), lessThan(1e-6), reason: '$end → $next');
        expect(step.distance, greaterThan(0));
      }
    }
  });

  test('связи одной пары разведены и не пересекаются, подписи не слипаются', () {
    // «Создал» и «изменил» — две связи между одними и теми же таблицами: без
    // разводки линии ложились друг на друга.
    final l = layout('USER ||--o{ DOC : created\nUSER ||--o{ DOC : changed\nUSER ||--o{ DOC : reviewed');
    final relations = relationsOf(l);
    final starts = [for (final r in relations) r.points.first.dx];
    final ends = [for (final r in relations) r.points.last.dx];

    expect(starts.toSet(), hasLength(3), reason: 'выходят из разных мест');
    expect(ends.toSet(), hasLength(3), reason: 'входят в разные места');
    // Порядок один и тот же у обеих таблиц — значит, линии не перекрещиваются.
    final order = [for (var i = 0; i < 3; i++) i]..sort((a, b) => starts[a].compareTo(starts[b]));
    final orderAtEnd = [for (var i = 0; i < 3; i++) i]..sort((a, b) => ends[a].compareTo(ends[b]));
    expect(orderAtEnd, order);

    final labels = [
      for (final label in l.shapes.whereType<DiagramLabel>())
        if (label.backdrop) label.at & label.run.size,
    ];
    for (var i = 0; i < labels.length; i++) {
      for (var j = i + 1; j < labels.length; j++) {
        expect(labels[i].inflate(4).overlaps(labels[j]), isFalse, reason: 'подписи $i и $j');
      }
    }
  });

  test('связь с собой — петля сбоку от таблицы', () {
    final l = layout('EMPLOYEE }o--o| EMPLOYEE : reports_to');
    final table = tablesOf(l).single;
    final loop = relationsOf(l).single;

    expect(onBorder(table, loop.points.first), isTrue);
    expect(onBorder(table, loop.points.last), isTrue);
    expect(loop.points.any((point) => point.dx > table.right), isTrue, reason: 'петля выходит наружу');
  });

  test('всё укладывается в объявленный размер', () {
    final l = layout(shop);
    final bounds = Offset.zero & l.size;

    for (final table in tablesOf(l)) {
      expect(bounds.inflate(0.01).contains(table.topLeft) && bounds.inflate(0.01).contains(table.bottomRight), isTrue);
    }
    for (final path in relationsOf(l)) {
      for (final point in path.points) {
        expect(bounds.inflate(0.01).contains(point), isTrue);
      }
    }
  });

  test('слева направо — сущности рядом, а не друг под другом', () {
    final tables = tablesOf(layout('direction LR\nA ||--o{ B : x'));

    expect(tables[1].left, greaterThan(tables[0].right));
  });

  test('повторяемость: та же врезка — те же координаты', () {
    List<Rect> once() => tablesOf(layout(shop));

    expect(once(), once());
    expect(
      [for (final path in relationsOf(layout(shop))) path.points],
      [for (final path in relationsOf(layout(shop))) path.points],
    );
  });
}
