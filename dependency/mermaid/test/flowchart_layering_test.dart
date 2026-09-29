import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Слои графа: снятие циклов, слои, фиктивные узлы, порядок.
///
/// Чистая комбинаторика — ни размеров, ни координат, и проверяется без замера
/// текста вовсе (`docs/spec/mermaid.md`, §7).
void main() {
  FlowLayering layer(String body) => layerFlowchart(parseFlowchart('flowchart TD\n$body'));

  /// Слой, на котором стоит узел.
  int layerOf(FlowLayering layering, String id) =>
      layering.layers.indexWhere((cells) => cells.any((cell) => cell.id == id));

  /// Слои в виде строк — по ним удобно и сравнивать, и читать отказ.
  List<String> shapeOf(FlowLayering layering) => [
    for (final cells in layering.layers)
      [for (final cell in cells) cell.isBend ? 'изгиб${cell.edge}' : cell.id!].join(','),
  ];

  group('слои', () {
    test('ребро ведёт со слоя на следующий', () {
      final layering = layer('A --> B --> C\n');

      expect(shapeOf(layering), ['A', 'B', 'C']);
    });

    test('у каждого неперевёрнутого ребра конец ниже начала', () {
      final layering = layer('A --> B\nA --> C\nB --> D\nC --> D\n');

      for (final chain in layering.chains) {
        if (chain.reversed || chain.selfLoop) {
          continue;
        }
        expect(chain.cells.last.layer, greaterThan(chain.cells.first.layer));
      }
    });

    test('слой — длиннейший путь, а не кратчайший', () {
      // `D` достижим и за один шаг, и за два: слой берётся по длинному.
      final layering = layer('A --> B --> C --> D\nA --> D\n');

      expect(layerOf(layering, 'D'), 3);
    });

    test('лишний знак в стрелке раздвигает слои', () {
      final layering = layer('A ---> B\n');

      expect(layerOf(layering, 'B'), 2);
    });

    test('узел без связей живёт на первом слое', () {
      final layering = layer('A --> B\nC\n');

      expect(layerOf(layering, 'C'), 0);
    });
  });

  group('снятие циклов', () {
    test('обратное ребро развёрнуто, а не выброшено', () {
      final layering = layer('A --> B --> C --> A\n');

      expect(layering.chains, hasLength(3));
      expect(layering.chains.where((chain) => chain.reversed), hasLength(1));
      // Узлы легли в цепочку; развёрнутое ребро идёт через два слоя и потому
      // получило перегиб — это и есть длинное ребро, а не ошибка.
      expect(shapeOf(layering), ['A', 'B,изгиб2', 'C']);
    });

    test('после снятия слои строго растут у всех дуг', () {
      // Тот самый инвариант: граф стал ациклическим.
      final layering = layer('A --> B --> C --> A\nC --> D --> B\n');

      for (final chain in layering.chains) {
        if (chain.selfLoop) {
          continue;
        }
        expect(chain.cells.last.layer, greaterThan(chain.cells.first.layer), reason: 'ребро ${chain.edge}');
      }
    });

    test('петля на себя слоёв не пересекает', () {
      final layering = layer('A --> B\nB --> B\n');

      final loop = layering.chains.firstWhere((chain) => chain.selfLoop);

      expect(loop.cells, hasLength(1));
      expect(loop.cells.single.id, 'B');
      expect(shapeOf(layering), ['A', 'B']);
    });
  });

  group('фиктивные узлы', () {
    test('длинное ребро получает перегиб на каждом промежуточном слое', () {
      final layering = layer('A --> B --> C\nA --> C\n');

      final long = layering.chains.firstWhere((chain) => chain.cells.length > 2);

      expect(long.cells.map((cell) => cell.layer), [0, 1, 2]);
      expect(long.cells[1].isBend, isTrue);
      expect(layering.layers[1].where((cell) => cell.isBend), hasLength(1));
    });

    test('после них ни одно ребро не длиннее слоя', () {
      final layering = layer('A --> B --> C --> D\nA --> D\nA --> C\n');

      for (final chain in layering.chains) {
        for (var i = 0; i + 1 < chain.cells.length; i++) {
          expect(chain.cells[i + 1].layer - chain.cells[i].layer, 1);
        }
      }
    });
  });

  group('порядок внутри слоя', () {
    test('места в слое — подряд и без повторов', () {
      final layering = layer('A --> C\nB --> C\nA --> D\nB --> D\n');

      for (final cells in layering.layers) {
        expect([for (final cell in cells) cell.order], [for (var i = 0; i < cells.length; i++) i]);
      }
    });

    test('начальный порядок — порядок объявления', () {
      // Ни одного ребра между слоями: двигать некуда, и остаётся текст.
      final layering = layer('B\nA\nC\n');

      expect(shapeOf(layering), ['B,A,C']);
    });

    test('пересечение, заданное текстом, расплетается', () {
      // Порядок объявления ставит на втором слое `P,Q`, а связи просят `Q,P`:
      // с текстовым порядком тут ровно одно пересечение.
      final layering = layer('P --> Z\nQ --> Z\nA --> Q\nB --> P\n');

      expect(shapeOf(layering)[1], 'Q,P', reason: 'объявление дало бы P,Q');
      expect(layering.crossings, 0);
    });

    test('пересечения не растут от прохода', () {
      // Полный двудольный: одно пересечение неизбежно, и оно не должно
      // размножиться.
      final layering = layer('A --> P\nA --> Q\nB --> P\nB --> Q\n');

      expect(layering.crossings, 1);
    });
  });

  group('подграфы', () {
    test('члены подграфа стоят подряд', () {
      // Эвристика тянет `W` ровно между `X` и `Y`: у каждого свой предок, и
      // медианы просят порядок X, W, Y. Удержание групп обязано это отменить.
      final layering = layer(
        'subgraph S\n  X --> Z\n  Y --> Z\nend\n'
        'P --> X\nQ --> W\nR --> Y\nW --> Z\n',
      );

      final members = {'X', 'Y'};
      for (final cells in layering.layers) {
        final places = [
          for (var i = 0; i < cells.length; i++)
            if (members.contains(cells[i].id)) i,
        ];
        if (places.length < 2) {
          continue;
        }
        expect(places.last - places.first, places.length - 1, reason: 'между своими вклинился чужой');
      }
    });

    test('вложенный подграф не разрывает внешний', () {
      final layering = layer(
        'subgraph Внешний\n'
        '  subgraph Внутренний\n'
        '    X --> Z\n'
        '    Y --> Z\n'
        '  end\n'
        '  W --> Z\n'
        'end\n'
        'P --> X\nQ --> V\nR --> Y\nS --> W\nV --> Z\n',
      );

      final outer = {'X', 'Y', 'W'};
      for (final cells in layering.layers) {
        final places = [
          for (var i = 0; i < cells.length; i++)
            if (outer.contains(cells[i].id)) i,
        ];
        if (places.length < 2) {
          continue;
        }
        expect(places.last - places.first, places.length - 1, reason: 'внешний подграф разорван');
      }
    });
  });

  test('одна и та же врезка раскладывается одинаково', () {
    // Дешёвая проверка, которая ловит случайный обход по множеству: без неё
    // эталон-снимок нечем сверять, а документ «пересобирался» бы при каждом
    // открытии.
    const source =
        'A --> B --> C --> A\n'
        'subgraph S\n  D --> E\nend\n'
        'B --> D\nE --> C\nA ---> E\n';

    expect(shapeOf(layer(source)), shapeOf(layer(source)));
  });

  group('пример целиком', () {
    const source = '''
flowchart LR
    Cli([Клиент]) --> API[Cloud API]
    API --> Check{order_number передан?}
    Check -- да --> CSO[(Учётная система)]
    Check -- нет --> T[/Терминал/]
    T -.-> API
    CSO --> Ready((Готово))
''';

    test('раскладывается и слои растут', () {
      final layering = layerFlowchart(parseFlowchart(source));

      expect(layering.layers.length, greaterThan(3));
      for (final chain in layering.chains) {
        if (chain.reversed || chain.selfLoop) {
          continue;
        }
        expect(chain.cells.last.layer, greaterThan(chain.cells.first.layer));
      }
    });

    test('возврат к API снят как цикл', () {
      final layering = layerFlowchart(parseFlowchart(source));

      expect(layering.chains.where((chain) => chain.reversed), hasLength(1));
    });
  });
}
