import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор `sequenceDiagram`: исходник → модель.
///
/// Без Flutter: проверяется обычными тестами, как и положено разбору.
void main() {
  SequenceDiagram parse(String body) => parseSequenceDiagram('sequenceDiagram\n$body');

  SequenceMessage messageAt(SequenceDiagram diagram, int index) => diagram.steps[index] as SequenceMessage;

  group('участники', () {
    test('объявленные идут в порядке объявления', () {
      final diagram = parse('participant B\nparticipant A\nA->>B: раз\n');

      expect(diagram.participants.map((p) => p.id), ['B', 'A']);
    });

    test('псевдоним становится подписью', () {
      final diagram = parse('participant Cli as Client\n');

      expect(diagram.participants.single.id, 'Cli');
      expect(diagram.participants.single.label, 'Client');
    });

    test('подпись бывает со скобками и по-русски', () {
      final diagram = parse('participant CSO as CSO (учётная система)\n');

      expect(diagram.participants.single.label, 'CSO (учётная система)');
    });

    test('`actor` рисуется иначе', () {
      final diagram = parse('actor U as Человек\nparticipant S\n');

      expect(diagram.participants.first.shape, ParticipantShape.person);
      expect(diagram.participants.last.shape, ParticipantShape.box);
    });

    test('незаявленный заводится на лету, в порядке появления', () {
      final diagram = parse('A->>B: раз\nC->>A: два\n');

      expect(diagram.participants.map((p) => p.id), ['A', 'B', 'C']);
      expect(diagram.participants.first.label, 'A', reason: 'подписи нет — берём имя');
    });

    test('повторное объявление уточняет подпись, а не заводит столбец', () {
      final diagram = parse('participant A\nparticipant A as Альфа\n');

      expect(diagram.participants, hasLength(1));
      expect(diagram.participants.single.label, 'Альфа');
    });
  });

  group('сообщения', () {
    test('стрелки разбираются все', () {
      const cases = {
        '->>': (ArrowHead.arrow, false),
        '-->>': (ArrowHead.arrow, true),
        '->': (ArrowHead.none, false),
        '-->': (ArrowHead.none, true),
        '-x': (ArrowHead.cross, false),
        '--x': (ArrowHead.cross, true),
        '-)': (ArrowHead.open, false),
        '--)': (ArrowHead.open, true),
      };

      for (final entry in cases.entries) {
        final diagram = parse('A${entry.key}B: текст\n');
        final arrow = messageAt(diagram, 0).arrow;

        expect(arrow.head, entry.value.$1, reason: entry.key);
        expect(arrow.dotted, entry.value.$2, reason: entry.key);
      }
    });

    test('подпись отделяется двоеточием и переносится по `<br/>`', () {
      final diagram = parse('A->>B: раз<br/>два\n');

      expect(messageAt(diagram, 0).label, ['раз', 'два']);
    });

    test('двоеточие внутри подписи её не рвёт', () {
      final diagram = parse('A->>B: время 10:30\n');

      expect(messageAt(diagram, 0).label, ['время 10:30']);
    });

    test('сообщение самому себе опознаётся', () {
      final diagram = parse('API->>API: счётчик локации 100…999\n');

      expect(messageAt(diagram, 0).isSelf, isTrue);
    });

    test('краткая отметка активности читается после стрелки', () {
      final open = parse('A->>+B: раз\n');
      expect(messageAt(open, 0).activates, isTrue);
      expect(messageAt(open, 0).to, 'B');

      final close = parse('A-->>-B: два\n');
      expect(messageAt(close, 0).deactivates, isTrue);
      expect(messageAt(close, 0).to, 'B', reason: 'минус — отметка, а не часть имени');
      expect(messageAt(close, 0).arrow.dotted, isTrue);
    });

    test('`activate` и `deactivate` отдельными строками', () {
      final diagram = parse('activate A\ndeactivate A\n');

      expect((diagram.steps.first as SequenceActivation).start, isTrue);
      expect((diagram.steps.last as SequenceActivation).start, isFalse);
    });
  });

  group('заметки', () {
    test('слева, справа и поверх', () {
      expect((parse('Note left of A: раз\n').steps.single as SequenceNote).placement, NotePlacement.leftOf);
      expect((parse('Note right of A: раз\n').steps.single as SequenceNote).placement, NotePlacement.rightOf);
      expect((parse('Note over A: раз\n').steps.single as SequenceNote).placement, NotePlacement.over);
    });

    test('поверх двоих', () {
      final note = parse('Note over A,B: общая\n').steps.single as SequenceNote;

      expect(note.of, ['A', 'B']);
    });
  });

  group('рамки', () {
    test('`alt` с `else` — две ветви', () {
      final diagram = parse('alt да\n  A->>B: раз\nelse нет\n  A->>B: два\nend\n');
      final block = diagram.steps.single as SequenceBlock;

      expect(block.kind, BlockKind.alt);
      expect(block.sections.map((s) => s.label), ['да', 'нет']);
      expect(block.sections.first.steps, hasLength(1));
    });

    test('`loop` и `opt` — по одной ветви', () {
      expect((parse('loop опрос\n  A->>B: раз\nend\n').steps.single as SequenceBlock).sections, hasLength(1));
      expect((parse('opt если\n  A->>B: раз\nend\n').steps.single as SequenceBlock).kind, BlockKind.opt);
    });

    test('`par` делится словом `and`', () {
      final block = parse('par одно\n  A->>B: раз\nand другое\n  A->>C: два\nend\n').steps.single as SequenceBlock;

      expect(block.kind, BlockKind.par);
      expect(block.sections.map((s) => s.label), ['одно', 'другое']);
    });

    test('рамки вкладываются', () {
      final diagram = parse('alt внешнее\n  alt внутреннее\n    A->>B: раз\n  end\nend\n');
      final outer = diagram.steps.single as SequenceBlock;
      final inner = outer.sections.single.steps.single as SequenceBlock;

      expect(inner.sections.single.label, 'внутреннее');
      expect(inner.sections.single.steps.single, isA<SequenceMessage>());
    });
  });

  group('отказы называют строку', () {
    void failsAt(String body, int line, {String? saying}) {
      try {
        parse(body);
        fail('ожидался отказ');
      } on MermaidError catch (error) {
        expect(error.line, line);
        if (saying != null) {
          expect(error.message, contains(saying));
        }
      }
    }

    test('лишний `end`', () => failsAt('A->>B: раз\nend\n', 3, saying: 'closes nothing'));

    test('незакрытая рамка указывает на её начало', () => failsAt('alt да\n  A->>B: раз\n', 2, saying: 'never closed'));

    test('`else` вне рамки', () => failsAt('else нет\n', 2, saying: 'no block is open'));

    test('непонятная строка', () => failsAt('совершенно непонятно\n', 2, saying: 'do not understand'));

    test('участник не назван', () => failsAt('participant\n', 2, saying: 'who the participant is'));

    test('заметка без текста', () => failsAt('Note over A\n', 2, saying: 'colon'));

    test('пустая врезка', () {
      try {
        parseSequenceDiagram('');
        fail('ожидался отказ');
      } on MermaidError catch (error) {
        expect(error.line, 1);
      }
    });
  });

  group('пример из задачи целиком', () {
    // Тот самый, ради которого этап и затевался: вложенные `alt`, `loop`,
    // `autonumber`, псевдонимы с кириллицей и скобками, сообщение самому себе.
    const source = '''
sequenceDiagram
    autonumber
    participant Cli as Client
    participant API as Cloud API
    participant T as Терминал локации
    participant CSO as CSO (учётная система)

    Cli->>API: POST /locations/{id}/orders
    API-->>Cli: 200 { order_id } — order_number ещё 0

    alt order_number передан клиентом
        API->>CSO: выгрузка заказа
    else order_number == 0
        alt нумерация от терминала локации (режим по умолчанию)
            API->>T: запрос номера и UPC
            T-->>API: { order_number, upc } — таймаут 20 с
        else внутренняя нумерация
            API->>API: счётчик локации 100…999
        end
        API->>CSO: выгрузка заказа
    end

    CSO-->>API: подтверждение приёма
    loop опрос клиента
        Cli->>API: GET /locations/{id}/orders/{order_id}
        API-->>Cli: заказ { order_number, processstatus, paymentstatus }
    end
''';

    test('разбирается без отказа', () {
      expect(() => parseSequenceDiagram(source), returnsNormally);
    });

    test('четыре участника, с подписями и в порядке объявления', () {
      final diagram = parseSequenceDiagram(source);

      expect(diagram.participants.map((p) => p.id), ['Cli', 'API', 'T', 'CSO']);
      expect(diagram.participants.map((p) => p.label), [
        'Client',
        'Cloud API',
        'Терминал локации',
        'CSO (учётная система)',
      ]);
    });

    test('нумерация включена', () {
      expect(parseSequenceDiagram(source).autonumber, isTrue);
    });

    test('шаги верхнего уровня: два сообщения, рамка, сообщение, рамка', () {
      final steps = parseSequenceDiagram(source).steps;

      expect(steps.map((s) => s.runtimeType.toString()), [
        'SequenceMessage',
        'SequenceMessage',
        'SequenceBlock',
        'SequenceMessage',
        'SequenceBlock',
      ]);
    });

    test('вложенная рамка на месте, и в ней — сообщение самому себе', () {
      final steps = parseSequenceDiagram(source).steps;
      final outer = steps[2] as SequenceBlock;
      final inner = outer.sections[1].steps.first as SequenceBlock;

      expect(outer.sections.map((s) => s.label), ['order_number передан клиентом', 'order_number == 0']);
      expect(inner.sections.map((s) => s.label), [
        'нумерация от терминала локации (режим по умолчанию)',
        'внутренняя нумерация',
      ]);

      final self = inner.sections[1].steps.single as SequenceMessage;
      expect(self.isSelf, isTrue);
      expect(self.from, 'API');
    });

    test('фигурные скобки и тире в подписях не мешают', () {
      final steps = parseSequenceDiagram(source).steps;

      expect((steps[1] as SequenceMessage).label, ['200 { order_id } — order_number ещё 0']);
      expect((steps[0] as SequenceMessage).label, ['POST /locations/{id}/orders']);
    });

    test('последняя рамка — цикл опроса', () {
      final loop = parseSequenceDiagram(source).steps.last as SequenceBlock;

      expect(loop.kind, BlockKind.loop);
      expect(loop.sections.single.label, 'опрос клиента');
      expect(loop.sections.single.steps, hasLength(2));
    });
  });
}
