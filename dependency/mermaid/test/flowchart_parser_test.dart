import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор `flowchart`: исходник → модель.
///
/// Без Flutter: проверяется обычными тестами, как и положено разбору.
void main() {
  FlowchartDiagram parse(String body) => parseFlowchart('flowchart TD\n$body');

  FlowNode nodeOf(FlowchartDiagram diagram, String id) => diagram.nodes.firstWhere((node) => node.id == id);

  group('объявление', () {
    test('направление по умолчанию — сверху вниз', () {
      expect(parseFlowchart('flowchart\nA --> B\n').direction, FlowDirection.topDown);
    });

    test('все четыре направления и оба написания вертикали', () {
      const cases = {
        'TD': FlowDirection.topDown,
        'TB': FlowDirection.topDown,
        'BT': FlowDirection.bottomUp,
        'LR': FlowDirection.leftRight,
        'RL': FlowDirection.rightLeft,
      };

      for (final entry in cases.entries) {
        expect(parseFlowchart('flowchart ${entry.key}\nA --> B\n').direction, entry.value, reason: entry.key);
      }
    });

    test('`graph` — прежнее имя того же', () {
      final diagram = parseFlowchart('graph LR\nA --> B\n');

      expect(diagram.direction, FlowDirection.leftRight);
      expect(diagram.edges, hasLength(1));
    });

    test('непонятное направление названо строкой', () {
      try {
        parseFlowchart('flowchart XY\nA --> B\n');
        fail('ожидался отказ');
      } on MermaidError catch (error) {
        expect(error.line, 1);
        expect(error.message, contains('direction'));
      }
    });
  });

  group('узлы', () {
    test('имя без скобок — узел с именем вместо подписи', () {
      final diagram = parse('A --> B\n');

      expect(diagram.nodes.map((node) => node.id), ['A', 'B']);
      expect(nodeOf(diagram, 'A').label, isEmpty);
      expect(nodeOf(diagram, 'A').text, ['A'], reason: 'подписи нет — показываем имя');
    });

    test('каждая форма опознаётся своими скобками', () {
      const cases = {
        'A[текст]': FlowShape.rect,
        'A(текст)': FlowShape.rounded,
        'A([текст])': FlowShape.stadium,
        'A[[текст]]': FlowShape.subroutine,
        'A[(текст)]': FlowShape.cylinder,
        'A((текст))': FlowShape.circle,
        'A{текст}': FlowShape.rhombus,
        'A{{текст}}': FlowShape.hexagon,
        'A[/текст/]': FlowShape.parallelogram,
        r'A[\текст\]': FlowShape.parallelogramAlt,
        r'A[/текст\]': FlowShape.trapezoid,
        r'A[\текст/]': FlowShape.trapezoidAlt,
        'A>текст]': FlowShape.flag,
      };

      for (final entry in cases.entries) {
        final node = parse('${entry.key} --> B\n').nodes.first;

        expect(node.shape, entry.value, reason: entry.key);
        expect(node.label, ['текст'], reason: entry.key);
      }
    });

    test('порядок узлов — порядок появления в тексте', () {
      final diagram = parse('B --> A\nC --> B\n');

      expect(diagram.nodes.map((node) => node.id), ['B', 'A', 'C']);
    });

    test('ссылка одним именем не стирает ни формы, ни подписи', () {
      final diagram = parse('A{Развилка} --> B\nA --> C\n');

      expect(nodeOf(diagram, 'A').shape, FlowShape.rhombus);
      expect(nodeOf(diagram, 'A').label, ['Развилка']);
    });

    test('повторное объявление уточняет форму и подпись', () {
      final diagram = parse('A --> B\nA[Начало] --> C\n');

      expect(nodeOf(diagram, 'A').label, ['Начало']);
      expect(diagram.nodes, hasLength(3), reason: 'узел один и тот же, а не второй');
    });

    test('подпись переносится по `<br/>` и живёт в кавычках', () {
      expect(parse('A[раз<br/>два] --> B\n').nodes.first.label, ['раз', 'два']);
      expect(parse('A["раз два"] --> B\n').nodes.first.label, ['раз два']);
    });

    test('дефис и равенство внутри подписи не рвут строку', () {
      // Ради этого сканер и считает скобки: иначе `раз-два` выглядит ребром.
      final diagram = parse('A[раз-два] --> B[три == четыре]\n');

      expect(diagram.edges, hasLength(1));
      expect(nodeOf(diagram, 'A').label, ['раз-два']);
      expect(nodeOf(diagram, 'B').label, ['три == четыре']);
    });

    test('имя класса через `:::` пропускается', () {
      final diagram = parse('A[Начало]:::важное --> B\n');

      expect(nodeOf(diagram, 'A').label, ['Начало']);
      expect(diagram.nodes.map((node) => node.id), ['A', 'B']);
    });
  });

  group('рёбра', () {
    FlowEdge edgeOf(String body) => parse(body).edges.single;

    test('линия и наконечник разбираются раздельно', () {
      const cases = {
        'A --> B': (FlowLine.solid, FlowEnd.arrow),
        'A --- B': (FlowLine.solid, FlowEnd.none),
        'A -.-> B': (FlowLine.dotted, FlowEnd.arrow),
        'A -.- B': (FlowLine.dotted, FlowEnd.none),
        'A ==> B': (FlowLine.thick, FlowEnd.arrow),
        'A === B': (FlowLine.thick, FlowEnd.none),
        'A --o B': (FlowLine.solid, FlowEnd.circle),
        'A --x B': (FlowLine.solid, FlowEnd.cross),
      };

      for (final entry in cases.entries) {
        final edge = edgeOf('${entry.key}\n');

        expect(edge.line, entry.value.$1, reason: entry.key);
        expect(edge.head, entry.value.$2, reason: entry.key);
        expect(edge.tail, FlowEnd.none, reason: entry.key);
      }
    });

    test('двусторонняя стрелка', () {
      final edge = edgeOf('A <--> B\n');

      expect(edge.tail, FlowEnd.arrow);
      expect(edge.head, FlowEnd.arrow);
    });

    test('подпись — обеими записями', () {
      expect(edgeOf('A -->|да| B\n').label, ['да']);
      expect(edgeOf('A -- да --> B\n').label, ['да']);
      expect(edgeOf('A -. да .-> B\n').label, ['да']);
      expect(edgeOf('A == да ==> B\n').label, ['да']);
    });

    test('подпись не путается с цепочкой', () {
      // `--- B -->` жадным началом читалось бы как одно ребро с подписью «B».
      final diagram = parse('A --- B --> C\n');

      expect(diagram.edges, hasLength(2));
      expect(diagram.edges.first.label, isEmpty);
      expect(diagram.nodes.map((node) => node.id), ['A', 'B', 'C']);
    });

    test('лишний знак прибавляет слой', () {
      expect(edgeOf('A --> B\n').span, 1);
      expect(edgeOf('A ---> B\n').span, 2);
      expect(edgeOf('A ----> B\n').span, 3);
      expect(edgeOf('A --- B\n').span, 1);
      expect(edgeOf('A ---- B\n').span, 2);
      expect(edgeOf('A ==> B\n').span, 1);
      expect(edgeOf('A ===> B\n').span, 2);
      expect(edgeOf('A -.-> B\n').span, 1);
      expect(edgeOf('A -..-> B\n').span, 2);
    });

    test('подпись длине не мешает', () {
      expect(edgeOf('A -- да ---> B\n').span, 2);
    });

    test('цепочка даёт по ребру на стрелку', () {
      final diagram = parse('A --> B --> C\n');

      expect(diagram.edges.map((edge) => '${edge.from}${edge.to}'), ['AB', 'BC']);
    });

    test('пучок через `&` — каждый с каждым', () {
      final diagram = parse('A & B --> C & D\n');

      expect(diagram.edges.map((edge) => '${edge.from}${edge.to}'), ['AC', 'AD', 'BC', 'BD']);
    });

    test('пучок со скобками в подписи', () {
      final diagram = parse('A[раз & два] & B --> C\n');

      expect(diagram.edges.map((edge) => '${edge.from}${edge.to}'), ['AC', 'BC']);
      expect(nodeOf(diagram, 'A').label, ['раз & два']);
    });

    test('без пробелов вокруг стрелки', () {
      final diagram = parse('A[Начало]-->B{Развилка}\n');

      expect(diagram.edges.single.from, 'A');
      expect(nodeOf(diagram, 'B').shape, FlowShape.rhombus);
    });
  });

  group('подграфы', () {
    test('узлы попадают в тот подграф, где встретились', () {
      final diagram = parse('A --> B\nsubgraph S\n  C --> D\nend\nD --> A\n');

      expect(diagram.subgraphs.single.id, 'S');
      expect(diagram.subgraphs.single.nodes, ['C', 'D']);
    });

    test('заголовок в скобках, а нет его — имя', () {
      expect(parse('subgraph S [Заголовок]\n  A --> B\nend\n').subgraphs.single.label, ['Заголовок']);
      expect(parse('subgraph S\n  A --> B\nend\n').subgraphs.single.text, ['S']);
    });

    test('вложенность записывается у родителя', () {
      final diagram = parse('subgraph Внешний\n  subgraph Внутренний\n    A --> B\n  end\n  C --> A\nend\n');

      final outer = diagram.subgraphs.firstWhere((group) => group.id == 'Внешний');
      final inner = diagram.subgraphs.firstWhere((group) => group.id == 'Внутренний');

      expect(inner.nodes, ['A', 'B']);
      expect(outer.nodes, ['C'], reason: 'A и B уже заняты вложенным');
      expect(outer.subgraphs, ['Внутренний']);
    });
  });

  group('оформление пропускается молча', () {
    test('строки оформления не роняют разбор и не заводят узлов', () {
      final diagram = parse(
        'A --> B\n'
        'style A fill:#f9f\n'
        'classDef важное fill:#bbf\n'
        'class A важное\n'
        'linkStyle 0 stroke:#f00\n'
        'click A "https://example.org"\n',
      );

      expect(diagram.nodes.map((node) => node.id), ['A', 'B']);
      expect(diagram.edges, hasLength(1));
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

    test('лишний `end`', () => failsAt('A --> B\nend\n', 3, saying: 'closes nothing'));

    test(
      'незакрытый подграф указывает на его начало',
      () => failsAt('subgraph S\n  A --> B\n', 2, saying: 'never closed'),
    );

    test('`direction` внутри подграфа', () {
      failsAt('subgraph S\n  direction LR\n  A --> B\nend\n', 3, saying: 'direction inside a subgraph');
    });

    test('невидимая связь', () => failsAt('A ~~~ B\n', 2, saying: 'invisible'));

    test('наконечники с обоих концов', () => failsAt('A o--o B\n', 2, saying: 'both ends'));

    test('у связи нет одного конца', () => failsAt('A --> \n', 2, saying: 'both of its ends'));

    test('подграф без имени', () => failsAt('subgraph\n  A --> B\nend\n', 2, saying: 'what the subgraph is'));

    test('непонятная форма', () => failsAt('A[раз) --> B\n', 2, saying: 'do not understand'));

    test('пустая врезка', () {
      try {
        parseFlowchart('');
        fail('ожидался отказ');
      } on MermaidError catch (error) {
        expect(error.line, 1);
      }
    });
  });

  group('пример целиком', () {
    const source = '''
flowchart LR
    Cli([Клиент]) --> API[Cloud API]
    API --> Check{order_number передан?}
    Check -- да --> CSO[(Учётная система)]
    Check -- нет --> T[/Терминал/]
    T -.-> API
    subgraph Опрос [Опрос статуса]
        direction_free[GET /orders] --> Ready((Готово))
    end
    CSO ==> Опрос
    style API fill:#f9f
''';

    test('разбирается без отказа', () {
      expect(() => parseFlowchart(source), returnsNormally);
    });

    test('направление, узлы и формы на месте', () {
      final diagram = parseFlowchart(source);

      expect(diagram.direction, FlowDirection.leftRight);
      expect(nodeOf(diagram, 'Cli').shape, FlowShape.stadium);
      expect(nodeOf(diagram, 'Check').shape, FlowShape.rhombus);
      expect(nodeOf(diagram, 'CSO').shape, FlowShape.cylinder);
      expect(nodeOf(diagram, 'T').shape, FlowShape.parallelogram);
      expect(nodeOf(diagram, 'Ready').shape, FlowShape.circle);
    });

    test('подписи развилки на месте', () {
      final diagram = parseFlowchart(source);
      final branches = diagram.edges.where((edge) => edge.from == 'Check').toList();

      expect(branches.map((edge) => edge.label.single), ['да', 'нет']);
    });

    test('подграф собрал своё', () {
      final diagram = parseFlowchart(source);

      expect(diagram.subgraphs.single.nodes, ['direction_free', 'Ready']);
      expect(diagram.subgraphs.single.label, ['Опрос статуса']);
    });

    test('пунктир и толстая различены', () {
      final diagram = parseFlowchart(source);

      expect(diagram.edges.firstWhere((edge) => edge.from == 'T').line, FlowLine.dotted);
      expect(diagram.edges.firstWhere((edge) => edge.from == 'CSO').line, FlowLine.thick);
    });
  });
}
