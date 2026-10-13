import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сглаженная кривая — `curveBasis` из d3, как у mermaid (`docs/spec/mermaid.md`,
/// §7а).
void main() {
  bool near(Offset a, Offset b) => (a - b).distance < 1e-9;

  test('начинается в первой точке и кончается в последней', () {
    const points = [Offset(0, 0), Offset(10, 30), Offset(50, 40), Offset(60, 90)];
    final curve = diagramBasis(points);

    expect(near(curve.first.from, points.first), isTrue);
    expect(near(curve.last.to, points.last), isTrue);
  });

  test('куски стыкуются без разрывов', () {
    final curve = diagramBasis(const [Offset(0, 0), Offset(10, 30), Offset(50, 40), Offset(60, 90), Offset(0, 120)]);

    for (var i = 1; i < curve.length; i++) {
      expect(near(curve[i - 1].to, curve[i].from), isTrue, reason: 'стык $i');
    }
  });

  test('касается первого и последнего отрезков — по ним ставятся знаки', () {
    const points = [Offset(0, 0), Offset(0, 12), Offset(0, 24), Offset(80, 60), Offset(80, 96), Offset(80, 108)];
    final samples = diagramSample(diagramBasis(points));

    // У конца, где две точки на одной прямой, кривая идёт по этой прямой.
    for (final point in samples.where((p) => p.dy <= 12)) {
      expect(point.dx.abs(), lessThan(1e-9), reason: 'у начала — по вертикали: $point');
    }
    for (final point in samples.where((p) => p.dy >= 96)) {
      expect((point.dx - 80).abs(), lessThan(1e-9), reason: 'у конца — по вертикали: $point');
    }
  });

  test('прямая остаётся прямой', () {
    final samples = diagramSample(diagramBasis(const [Offset(0, 0), Offset(10, 10), Offset(20, 20), Offset(30, 30)]));

    for (final point in samples) {
      expect((point.dx - point.dy).abs(), lessThan(1e-9));
    }
  });

  test('две точки — отрезок', () {
    final curve = diagramBasis(const [Offset(0, 0), Offset(10, 0)]);

    expect(curve, hasLength(1));
    expect(near(diagramCubicAt(curve.single, 0.5), const Offset(5, 0)), isTrue);
  });
}
