import 'dart:ui';

import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Замер с постоянной шириной знака: координаты становятся точными числами, и
/// утверждения — осмысленными (`docs/spec/mermaid.md`, §7).
class _FakeMeasure implements DiagramTextMeasure {
  const _FakeMeasure();

  static const double charWidth = 7;
  static const double lineHeight = 16;

  @override
  DiagramTextRun run(String text, DiagramTextRole role, {double maxWidth = double.infinity}) {
    final lines = text.split('\n');
    final widest = lines.map((line) => line.length).fold(0, (a, b) => a > b ? a : b);

    return _FakeRun(Size(widest * charWidth, lines.length * lineHeight));
  }
}

class _FakeRun implements DiagramTextRun {
  const _FakeRun(this.size);

  @override
  final Size size;

  @override
  void paint(Canvas canvas, Offset at) {}
}

void main() {
  const measure = _FakeMeasure();

  FlowGeometry place(String source) {
    final diagram = parseFlowchart(source);

    return placeFlowchart(diagram, layerFlowchart(diagram), measure);
  }

  FlowGeometry down(String body) => place('flowchart TD\n$body');

  Rect rectOf(FlowGeometry geometry, String id) => geometry.boxes[id]!.rect;

  group('размер фигуры', () {
    test('подпись длиннее — фигура шире', () {
      final geometry = down('A[раз] --> B[очень длинная подпись]\n');

      expect(rectOf(geometry, 'B').width, greaterThan(rectOf(geometry, 'A').width));
    });

    test('ромбу нужно вдвое больше: текст вписан по диагоналям', () {
      final geometry = down('A[текст] --> B{текст}\n');

      expect(rectOf(geometry, 'B').width, greaterThan(rectOf(geometry, 'A').width * 1.5));
      expect(rectOf(geometry, 'B').height, greaterThan(rectOf(geometry, 'A').height * 1.5));
    });

    test('круг квадратный, и подпись влезает по диагонали', () {
      final geometry = down('A((длинная подпись)) --> B\n');
      final circle = rectOf(geometry, 'A');

      expect(circle.width, circle.height);
      expect(circle.width, greaterThan(geometry.boxes['A']!.text.size.width));
    });

    test('скошенным нужен запас по краям', () {
      final geometry = down('A[текст] --> B[/текст/]\n');

      expect(rectOf(geometry, 'B').width, greaterThan(rectOf(geometry, 'A').width));
      expect(rectOf(geometry, 'B').height, rectOf(geometry, 'A').height);
    });

    test('узел с коротким именем не выходит точкой', () {
      final geometry = down('A --> B\n');

      expect(rectOf(geometry, 'A').width, greaterThanOrEqualTo(const FlowMetrics().minWidth));
      expect(rectOf(geometry, 'A').height, greaterThanOrEqualTo(const FlowMetrics().minHeight));
    });
  });

  group('места', () {
    test('соседи по слою не налезают друг на друга', () {
      final geometry = down('A --> P\nA --> Q\nA --> R\nP --> Z\nQ --> Z\nR --> Z\n');

      for (final cells in geometry.layering.layers) {
        final rects = [
          for (final cell in cells)
            if (!cell.isBend) rectOf(geometry, cell.id!),
        ]..sort((a, b) => a.left.compareTo(b.left));

        for (var i = 0; i + 1 < rects.length; i++) {
          expect(rects[i].right, lessThanOrEqualTo(rects[i + 1].left), reason: 'соседи $i и ${i + 1}');
        }
      }
    });

    test('родитель стоит над серединой своих детей', () {
      // Ради этого узлы и подтягиваются к медиане соседей: иначе всё липнет к
      // левому краю, и связи читаются как попало.
      final geometry = down('A --> P\nA --> Q\n');
      final middle = (rectOf(geometry, 'P').center.dx + rectOf(geometry, 'Q').center.dx) / 2;

      expect(rectOf(geometry, 'A').center.dx, moreOrLessEquals(middle, epsilon: 0.5));
      expect(rectOf(geometry, 'P').center.dx, isNot(moreOrLessEquals(middle, epsilon: 0.5)));
    });

    test('слои не налезают друг на друга', () {
      final geometry = down('A --> B --> C\nA --> C\n');

      var bottom = -double.infinity;
      for (final cells in geometry.layering.layers) {
        final boxes = [
          for (final cell in cells)
            if (!cell.isBend) rectOf(geometry, cell.id!),
        ];
        if (boxes.isEmpty) {
          continue;
        }
        final top = boxes.map((rect) => rect.top).reduce((a, b) => a < b ? a : b);
        expect(top, greaterThan(bottom));
        bottom = boxes.map((rect) => rect.bottom).reduce((a, b) => a > b ? a : b);
      }
    });

    test('всё укладывается в объявленный размер', () {
      final geometry = down(
        'subgraph S [Заголовок подграфа]\n  X --> Y\nend\n'
        'A -- длинная подпись --> X\nY --> Z\nA ---> Z\n',
      );
      final field = Offset.zero & geometry.size;

      for (final box in geometry.boxes.values) {
        expect(field.contains(box.rect.topLeft), isTrue, reason: box.id);
        expect(field.contains(box.rect.bottomRight), isTrue, reason: box.id);
      }
      for (final frame in geometry.frames) {
        expect(field.contains(frame.rect.topLeft), isTrue, reason: frame.id);
        expect(field.contains(frame.rect.bottomRight), isTrue, reason: frame.id);
      }
      for (final label in geometry.labels) {
        expect(field.contains(label.at), isTrue);
      }
    });

    test('высокая подпись ребра раздвигает слои, а не наезжает на узлы', () {
      // Высокая, а не длинная: между слоями подпись растёт поперёк, и раздвигает
      // их именно высота. Одной строке отведённого зазора хватает и так.
      final plain = down('A --> B\n');
      final titled = down('A -- раз<br/>два<br/>три<br/>четыре --> B\n');

      expect(titled.size.height, greaterThan(plain.size.height));
      expect(
        titled.boxes['B']!.rect.top - titled.boxes['A']!.rect.bottom,
        greaterThan(plain.boxes['B']!.rect.top - plain.boxes['A']!.rect.bottom),
      );
    });

    test('длинная подпись ребра умещается в картинку целиком', () {
      final geometry = down('A -- очень длинная подпись ребра --> B\n');
      final label = geometry.labels.single;

      expect((Offset.zero & geometry.size).contains(label.at + Offset(label.run.size.width, 0)), isTrue);
    });
  });

  group('направление', () {
    test('сверху вниз — конец ниже начала', () {
      final geometry = place('flowchart TD\nA --> B\n');

      expect(rectOf(geometry, 'B').top, greaterThan(rectOf(geometry, 'A').bottom));
    });

    test('снизу вверх — конец выше начала', () {
      final geometry = place('flowchart BT\nA --> B\n');

      expect(rectOf(geometry, 'B').bottom, lessThan(rectOf(geometry, 'A').top));
    });

    test('слева направо — конец правее начала', () {
      final geometry = place('flowchart LR\nA --> B\n');

      expect(rectOf(geometry, 'B').left, greaterThan(rectOf(geometry, 'A').right));
    });

    test('справа налево — конец левее начала', () {
      final geometry = place('flowchart RL\nA --> B\n');

      expect(rectOf(geometry, 'B').right, lessThan(rectOf(geometry, 'A').left));
    });

    test('подпись не поворачивается вместе с картинкой', () {
      // Ради этого меняются оси, а не готовые координаты: у повёрнутой коробки
      // широкий текст оказался бы в узкой и высокой рамке.
      final vertical = place('flowchart TD\nA[очень длинная подпись] --> B\n');
      final horizontal = place('flowchart LR\nA[очень длинная подпись] --> B\n');

      expect(rectOf(horizontal, 'A').size, rectOf(vertical, 'A').size);
    });
  });

  group('рамки подграфов', () {
    const source =
        'flowchart TD\n'
        'subgraph S [Свои]\n'
        '  X --> Y\n'
        'end\n'
        'A --> X\nA --> W\nY --> Z\nW --> Z\n';

    test('рамка накрывает своих', () {
      final geometry = place(source);
      final frame = geometry.frames.single;

      for (final id in ['X', 'Y']) {
        expect(frame.rect.contains(rectOf(geometry, id).topLeft), isTrue, reason: id);
        expect(frame.rect.contains(rectOf(geometry, id).bottomRight), isTrue, reason: id);
      }
    });

    test('и не накрывает чужих', () {
      final geometry = place(source);
      final frame = geometry.frames.single;

      for (final id in ['A', 'W', 'Z']) {
        expect(frame.rect.overlaps(rectOf(geometry, id)), isFalse, reason: id);
      }
    });

    test('заголовок стоит внутри рамки, над содержимым', () {
      final geometry = place(source);
      final frame = geometry.frames.single;

      expect(frame.rect.contains(frame.titleAt), isTrue);
      expect(frame.titleAt.dy, lessThan(rectOf(geometry, 'X').top));
    });

    test('вложенная рамка внутри внешней', () {
      final geometry = place(
        'flowchart TD\n'
        'subgraph Внешний\n'
        '  subgraph Внутренний\n'
        '    X --> Y\n'
        '  end\n'
        '  W --> Y\n'
        'end\n'
        'A --> X\nA --> W\n',
      );

      final outer = geometry.frames.firstWhere((frame) => frame.id == 'Внешний');
      final inner = geometry.frames.firstWhere((frame) => frame.id == 'Внутренний');

      expect(outer.rect.contains(inner.rect.topLeft), isTrue);
      expect(outer.rect.contains(inner.rect.bottomRight), isTrue);
    });
  });

  test('одна и та же врезка расставляется одинаково', () {
    const source =
        'flowchart LR\n'
        'A --> B --> C --> A\n'
        'subgraph S\n  D --> E\nend\n'
        'B --> D\nE --> C\nA ---> E\n';

    String shapeOf(FlowGeometry geometry) =>
        [for (final id in geometry.boxes.keys) '$id ${geometry.boxes[id]!.rect}'].join('; ');

    expect(shapeOf(place(source)), shapeOf(place(source)));
  });
}
