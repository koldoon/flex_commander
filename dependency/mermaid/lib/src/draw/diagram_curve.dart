import 'dart:ui';

/// Кусок кривой: отрезок или кубическая кривая Безье.
///
/// Отрезок — это кубическая с опорами на самих концах; так проще и
/// рисовать, и мерить.
typedef DiagramCubic = ({Offset from, Offset c1, Offset c2, Offset to});

/// Сглаженная кривая по точкам маршрута — `curveBasis` из d3, им рисует связи
/// mermaid (`docs/spec/mermaid.md`, §7а).
///
/// Однородный кубический B-сплайн, прижатый к концам: кривая начинается в
/// первой точке и кончается в последней, касаясь там первого и последнего
/// отрезков, а через промежуточные точки не проходит — они её тянут. Отсюда и
/// правило для маршрута: точка «на шаг от рамки» задаёт, под каким углом
/// линия выходит из таблицы.
///
/// Чистый расчёт без холста: по нему рисует рисовальщик и по нему же раскладка
/// ставит подписи на саму кривую.
List<DiagramCubic> diagramBasis(List<Offset> points) {
  if (points.length < 2) {
    return const [];
  }
  if (points.length == 2) {
    return [_line(points[0], points[1])];
  }

  // Перенос `d3-shape/src/curve/basis.js` один в один: состояние — две
  // последние точки и счётчик.
  final out = <DiagramCubic>[];
  var at = points[0];
  var p0 = points[0];
  var p1 = points[1];

  void basis(Offset next) {
    final to = Offset((p0.dx + 4 * p1.dx + next.dx) / 6, (p0.dy + 4 * p1.dy + next.dy) / 6);
    out.add((
      from: at,
      c1: Offset((2 * p0.dx + p1.dx) / 3, (2 * p0.dy + p1.dy) / 3),
      c2: Offset((p0.dx + 2 * p1.dx) / 3, (p0.dy + 2 * p1.dy) / 3),
      to: to,
    ));
    at = to;
  }

  // Третья точка: прямой кусок до (5·p0 + p1)/6, дальше — кривые.
  final start = Offset((5 * p0.dx + p1.dx) / 6, (5 * p0.dy + p1.dy) / 6);
  out.add(_line(at, start));
  at = start;

  for (final next in points.skip(2)) {
    basis(next);
    p0 = p1;
    p1 = next;
  }

  // Конец: ещё одна кривая к последней точке и прямой кусок в неё.
  basis(p1);
  out.add(_line(at, p1));

  return out;
}

DiagramCubic _line(Offset from, Offset to) => (from: from, c1: from, c2: to, to: to);

/// Точка кубической кривой при параметре [t] от 0 до 1.
Offset diagramCubicAt(DiagramCubic cubic, double t) {
  final u = 1 - t;

  return cubic.from * (u * u * u) + cubic.c1 * (3 * u * u * t) + cubic.c2 * (3 * u * t * t) + cubic.to * (t * t * t);
}

/// Кривая ломаной: [perPiece] точек на каждый кусок. Ею мерят длину и ставят
/// подписи.
List<Offset> diagramSample(List<DiagramCubic> curve, {int perPiece = 12}) => [
  if (curve.isNotEmpty) curve.first.from,
  for (final cubic in curve)
    for (var i = 1; i <= perPiece; i++) diagramCubicAt(cubic, i / perPiece),
];
