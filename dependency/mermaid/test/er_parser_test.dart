import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор `erDiagram`: исходник → модель (`docs/spec/mermaid.md`, §7а).
///
/// Без Flutter: проверяется обычными тестами, как и положено разбору.
void main() {
  ErDiagram parse(String body) => parseErDiagram('erDiagram\n$body');

  ErEntity entityOf(ErDiagram diagram, String id) => diagram.entities.firstWhere((entity) => entity.id == id);

  /// Номер строки, на которую указал отказ.
  int refusedAt(String body) {
    try {
      parse(body);
    } on MermaidError catch (error) {
      return error.line;
    }
    fail('ждали отказа, а разбор прошёл');
  }

  group('связи', () {
    test('кардинальность значками — каждая с обеих сторон', () {
      const left = {'|o': ErCard.zeroOrOne, '||': ErCard.exactlyOne, '}o': ErCard.zeroOrMore, '}|': ErCard.oneOrMore};
      const right = {'o|': ErCard.zeroOrOne, '||': ErCard.exactlyOne, 'o{': ErCard.zeroOrMore, '|{': ErCard.oneOrMore};

      for (final l in left.entries) {
        for (final r in right.entries) {
          final relation = parse('A ${l.key}--${r.key} B : x').relations.single;
          expect(relation.fromCard, l.value, reason: '${l.key}--${r.key}');
          expect(relation.toCard, r.value, reason: '${l.key}--${r.key}');
        }
      }
    });

    test('`--` — идентифицирующая, `..` — нет', () {
      expect(parse('A ||--o{ B : x').relations.single.identifying, isTrue);
      expect(parse('A ||..o{ B : x').relations.single.identifying, isFalse);
    });

    test('стороны: левая сущность — from, правая — to', () {
      final relation = parse('CUSTOMER ||--o{ ORDER : places').relations.single;

      expect(relation.from, 'CUSTOMER');
      expect(relation.to, 'ORDER');
      expect(relation.label, 'places');
    });

    test('подпись словом, в кавычках и пустая', () {
      expect(parse('A ||--o{ B : places').relations.single.label, 'places');
      expect(parse('A ||--o{ B : "places an order"').relations.single.label, 'places an order');
      expect(parse('A ||--o{ B : ""').relations.single.label, '');
    });

    test('кардинальность словами', () {
      final identifying = parse('A one or more to zero or many B : x').relations.single;
      expect(identifying.fromCard, ErCard.oneOrMore);
      expect(identifying.toCard, ErCard.zeroOrMore);
      expect(identifying.identifying, isTrue);

      final optional = parse('A only one optionally to 0+ B : x').relations.single;
      expect(optional.fromCard, ErCard.exactlyOne);
      expect(optional.toCard, ErCard.zeroOrMore);
      expect(optional.identifying, isFalse);

      expect(parse('A zero or one to 1+ B : x').relations.single.fromCard, ErCard.zeroOrOne);
      expect(parse('A many(0) to many(1) B : x').relations.single.toCard, ErCard.oneOrMore);
    });

    test('без пробелов вокруг значков и с дефисом в имени', () {
      final relation = parse('ORDER||--|{LINE-ITEM : contains').relations.single;

      expect(relation.from, 'ORDER');
      expect(relation.to, 'LINE-ITEM');
    });

    test('сущность из связи заводится по первой встрече, в порядке появления', () {
      final diagram = parse('CUSTOMER ||--o{ ORDER : places\nORDER ||--|{ ITEM : contains');

      expect([for (final entity in diagram.entities) entity.id], ['CUSTOMER', 'ORDER', 'ITEM']);
      expect(entityOf(diagram, 'ITEM').attributes, isEmpty);
    });

    test('связь сущности с собой', () {
      final relation = parse('EMPLOYEE }o--o| EMPLOYEE : reports_to').relations.single;

      expect(relation.from, relation.to);
    });
  });

  group('сущности', () {
    test('атрибуты: тип, имя, ключи, комментарий', () {
      final entity = entityOf(
        parse('CUSTOMER {\n  string name\n  int id PK "the key"\n  varchar(255) email UK\n  int org FK, UK\n}'),
        'CUSTOMER',
      );

      expect(entity.attributes, hasLength(4));
      expect(entity.attributes[0].type, 'string');
      expect(entity.attributes[0].name, 'name');
      expect(entity.attributes[0].keys, isEmpty);
      expect(entity.attributes[1].keys, [ErKey.pk]);
      expect(entity.attributes[1].comment, 'the key');
      expect(entity.attributes[2].type, 'varchar(255)');
      expect(entity.attributes[2].keys, [ErKey.uk]);
      expect(entity.attributes[3].keys, [ErKey.fk, ErKey.uk]);
    });

    test('тип массивом и комментарий без ключа', () {
      final attribute = entityOf(parse('A {\n  string[] tags "comma list"\n}'), 'A').attributes.single;

      expect(attribute.type, 'string[]');
      expect(attribute.keys, isEmpty);
      expect(attribute.comment, 'comma list');
    });

    test('одиночная, пустым блоком, псевдонимом и в кавычках', () {
      final diagram = parse('LONE\nEMPTY { }\np[Person]\n"Customer Account" {\n  int id\n}');

      expect(entityOf(diagram, 'LONE').label, 'LONE');
      expect(entityOf(diagram, 'EMPTY').attributes, isEmpty);
      expect(entityOf(diagram, 'p').label, 'Person');
      expect(entityOf(diagram, 'Customer Account').attributes.single.name, 'id');
    });

    test('псевдоним, объявленный после связи, уточняет подпись', () {
      final diagram = parse('p ||--o{ o : makes\np[Person]');

      expect(entityOf(diagram, 'p').label, 'Person');
    });

    test('кириллица в именах', () {
      final diagram = parse('Покупатель ||--o{ Заказ : делает');

      expect(diagram.relations.single.to, 'Заказ');
    });
  });

  group('объявление и оформление', () {
    test('направление: по умолчанию сверху вниз, `direction` меняет', () {
      expect(parse('A ||--o{ B : x').direction, FlowDirection.topDown);
      expect(parse('direction LR\nA ||--o{ B : x').direction, FlowDirection.leftRight);
    });

    test('оформление пропускается молча', () {
      final diagram = parse('A ||--o{ B : x\nstyle A fill:#f9f\nclassDef hot fill:#f00\nclass A hot\nC:::hot');

      expect(diagram.relations, hasLength(1));
      expect([for (final entity in diagram.entities) entity.id], ['A', 'B', 'C']);
    });
  });

  group('отказы называют строку', () {
    test('незакрытый блок — строка, где он открыт', () {
      expect(refusedAt('A ||--o{ B : x\nB {\n  int id\n'), 3);
    });

    test('лишняя скобка', () {
      expect(refusedAt('A ||--o{ B : x\n}'), 3);
    });

    test('непонятная кардинальность', () {
      expect(refusedAt('A ||--o{ B : x\nA <>--o{ B : x'), 3);
      expect(refusedAt('A -- B : x'), 2);
    });

    test('связь без подписи', () {
      expect(refusedAt('A ||--o{ B'), 2);
    });

    test('атрибут без имени', () {
      expect(refusedAt('A {\n  int\n}'), 3);
    });

    test('непонятная строка', () {
      expect(refusedAt('A ||--o{ B : x\n@@@'), 3);
    });

    test('непонятное направление', () {
      expect(refusedAt('direction XY'), 2);
    });
  });
}
