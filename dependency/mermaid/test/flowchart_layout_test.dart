import 'dart:ui';

import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Замер с постоянной шириной знака: координаты становятся точными числами.
class _FakeMeasure implements DiagramTextMeasure {
  const _FakeMeasure();

  @override
  DiagramTextRun run(String text, DiagramTextRole role, {double maxWidth = double.infinity}) {
    final lines = text.split('\n');
    final widest = lines.map((line) => line.length).fold(0, (a, b) => a > b ? a : b);

    return _FakeRun(Size(widest * 7, lines.length * 16));
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

  DiagramLayout layout(String source) => layoutFlowchart(parseFlowchart(source), measure);
  DiagramLayout down(String body) => layout('flowchart TD\n$body');

  List<DiagramFigure> figuresOf(DiagramLayout l) => l.shapes.whereType<DiagramFigure>().toList();
  List<DiagramPath> pathsOf(DiagramLayout l) => l.shapes.whereType<DiagramPath>().toList();
  List<DiagramLabel> labelsOf(DiagramLayout l) => l.shapes.whereType<DiagramLabel>().toList();

  /// Стрелки: у них есть наконечник, и они не черты фигур.
  List<DiagramPath> arrowsOf(DiagramLayout l) => pathsOf(l).where((p) => p.head != DiagramHead.none).toList();

  group('фигуры', () {
    test('каждый узел рисуется своей фигурой', () {
      final l = down('A[раз] --> B{два} --> C((три))\n');

      expect(figuresOf(l), hasLength(3));
    });

    test('ромб не прямоугольник: угол внутри фигуры пуст', () {
      final l = down('A{развилка}\n');
      final figure = figuresOf(l).single;
      final bounds = figure.path.getBounds();

      expect(figure.path.contains(bounds.center), isTrue, reason: 'середина ромба — внутри');
      expect(figure.path.contains(bounds.topLeft + const Offset(2, 2)), isFalse, reason: 'угол должен быть срезан');
    });

    test('круг круглый', () {
      final l = down('A((круг))\n');
      final figure = figuresOf(l).single;
      final bounds = figure.path.getBounds();

      expect(bounds.width, moreOrLessEquals(bounds.height, epsilon: 0.01));
      expect(figure.path.contains(bounds.topLeft + const Offset(2, 2)), isFalse);
    });

    test('у подпрограммы есть боковые черты, у прямоугольника — нет', () {
      expect(pathsOf(down('A[[вызов]]\n')).where((p) => p.head == DiagramHead.none), hasLength(2));
      expect(pathsOf(down('A[обычный]\n')), isEmpty);
    });

    test('у цилиндра есть крышка отдельной незалитой фигурой', () {
      final l = down('A[(хранилище)]\n');

      expect(figuresOf(l).where((figure) => !figure.filled), hasLength(1));
    });

    test('подпись стоит по центру своей фигуры', () {
      final l = down('A[подпись]\n');
      final figure = figuresOf(l).single;
      final label = labelsOf(l).single;
      final centre = label.at + Offset(label.run.size.width / 2, label.run.size.height / 2);

      expect(centre.dx, moreOrLessEquals(figure.path.getBounds().center.dx, epsilon: 0.01));
      expect(centre.dy, moreOrLessEquals(figure.path.getBounds().center.dy, epsilon: 0.01));
    });
  });

  group('рёбра', () {
    test('конец упирается в границу фигуры, а не в её центр', () {
      final l = down('A --> B\n');
      final arrow = arrowsOf(l).single;
      final target = figuresOf(l).last.path.getBounds();

      expect(target.contains(arrow.points.last) || _onEdge(target, arrow.points.last), isTrue);
      expect((arrow.points.last - target.center).distance, greaterThan(1), reason: 'наконечник утонул в узле');
    });

    test('вид линии и наконечник доезжают до отрисовки', () {
      expect(arrowsOf(down('A -.-> B\n')).single.dashed, isTrue);
      expect(arrowsOf(down('A ==> B\n')).single.thick, isTrue);
      expect(arrowsOf(down('A --o B\n')).single.head, DiagramHead.circle);
      expect(arrowsOf(down('A --x B\n')).single.head, DiagramHead.cross);
      expect(arrowsOf(down('A <--> B\n')).single.tail, DiagramHead.arrow);
    });

    test('развёрнутое ребро рисуется в свою настоящую сторону', () {
      // `C --> A` снято как цикл, но наконечник обязан быть у `A`.
      final l = down('A --> B --> C --> A\n');
      final boxes = {
        for (final node in ['A', 'B', 'C']) node: figuresOf(l)[['A', 'B', 'C'].indexOf(node)].path.getBounds(),
      };

      final back = arrowsOf(l).firstWhere((path) => (path.points.last - boxes['A']!.center).distance < 40);

      expect(back.points.first.dy, greaterThan(back.points.last.dy), reason: 'ведёт снизу вверх, к `A`');
    });

    test('петля на себя рисуется сбоку', () {
      final l = down('A --> A\n');
      final loop = arrowsOf(l).single;

      expect(loop.points, hasLength(4));
      expect(loop.points[1].dx, greaterThan(figuresOf(l).single.path.getBounds().right));
    });

    test('длинное ребро идёт через перегиб', () {
      final l = down('A --> B --> C\nA --> C\n');
      final long = arrowsOf(l).firstWhere((path) => path.points.length > 2);

      expect(long.points, hasLength(3));
    });
  });

  group('подграфы', () {
    test('рамка — незалитая коробка с заголовком', () {
      final l = down('subgraph S [Заголовок]\n  A --> B\nend\n');

      final frame = l.shapes.whereType<DiagramBox>().single;

      expect(frame.filled, isFalse);
      expect(
        labelsOf(l).map((label) => label.run.size.width),
        contains(measure.run('Заголовок', DiagramTextRole.blockLabel).size.width),
      );
    });

    test('рамка рисуется раньше содержимого', () {
      // Иначе её черта легла бы поверх узлов.
      final l = down('subgraph S\n  A --> B\nend\n');
      final frame = l.shapes.indexWhere((shape) => shape is DiagramBox);
      final figure = l.shapes.indexWhere((shape) => shape is DiagramFigure);

      expect(frame, isNonNegative);
      expect(frame, lessThan(figure));
    });
  });

  test('всё умещается в объявленный размер', () {
    final l = down(
      'subgraph S [Свои]\n  X --> Y\nend\n'
      'A -- подпись --> X\nY --> Z\nA ---> Z\nZ --> Z\n',
    );

    for (final shape in l.shapes) {
      switch (shape) {
        case DiagramBox(:final rect):
          expect(rect.right, lessThanOrEqualTo(l.size.width + 0.01));
          expect(rect.bottom, lessThanOrEqualTo(l.size.height + 0.01));
        case DiagramFigure(:final path):
          expect(path.getBounds().right, lessThanOrEqualTo(l.size.width + 0.01));
          expect(path.getBounds().bottom, lessThanOrEqualTo(l.size.height + 0.01));
        case DiagramPath(:final points):
          for (final point in points) {
            expect(point.dx, lessThanOrEqualTo(l.size.width + 0.01));
            expect(point.dy, lessThanOrEqualTo(l.size.height + 0.01));
          }
        case DiagramLabel(:final at, :final run):
          expect(at.dx + run.size.width, lessThanOrEqualTo(l.size.width + 0.01));
          expect(at.dy + run.size.height, lessThanOrEqualTo(l.size.height + 0.01));
      }
    }
  });

  test('одна и та же врезка рисуется одинаково', () {
    const source =
        'flowchart LR\n'
        'A --> B --> C --> A\n'
        'subgraph S\n  D --> E\nend\n'
        'B --> D\nE --> C\nA ---> E\n';

    String shapeOf(DiagramLayout l) => [
      for (final shape in l.shapes)
        switch (shape) {
          DiagramBox(:final rect) => 'коробка $rect',
          DiagramFigure(:final path) => 'фигура ${path.getBounds()}',
          DiagramPath(:final points) => 'линия $points',
          DiagramLabel(:final at) => 'надпись $at',
        },
    ].join('; ');

    expect(shapeOf(layout(source)), shapeOf(layout(source)));
  });
}

/// Точка на рамке — с запасом на погрешность.
bool _onEdge(Rect rect, Offset point) =>
    (point.dx - rect.left).abs() < 0.5 ||
    (point.dx - rect.right).abs() < 0.5 ||
    (point.dy - rect.top).abs() < 0.5 ||
    (point.dy - rect.bottom).abs() < 0.5;
