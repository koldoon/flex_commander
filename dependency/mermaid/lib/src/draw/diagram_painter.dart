import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'diagram_curve.dart';
import 'diagram_layout.dart';
import 'diagram_theme.dart';

/// Рисует готовые фигуры. Ничего не считает: всё посчитано раскладкой.
class DiagramPainter extends CustomPainter {
  const DiagramPainter({required this.layout, required this.style});

  final DiagramLayout layout;
  final DiagramStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in layout.shapes) {
      switch (shape) {
        case DiagramBox():
          _box(canvas, shape);
        case DiagramFigure():
          _figure(canvas, shape);
        case DiagramPath():
          _path(canvas, shape);
        case DiagramLabel(:final run, :final at, :final backdrop):
          if (backdrop) {
            // Подложка чуть шире надписи: вплотную к буквам линия всё равно
            // просвечивала бы.
            canvas.drawRect(
              Rect.fromLTWH(at.dx - 2, at.dy - 1, run.size.width + 4, run.size.height + 2),
              Paint()..color = style.background,
            );
          }
          run.paint(canvas, at);
      }
    }
  }

  void _box(Canvas canvas, DiagramBox box) {
    final rect = RRect.fromRectAndRadius(box.rect, Radius.circular(box.radius));

    if (box.filled) {
      canvas.drawRRect(rect, Paint()..color = style.colorOf(box.ink));
      // Плашка — без обводки. Обводка того же цвета ложилась поверх
      // полупрозрачной заливки, прозрачность складывалась, и край выходил
      // светлее — рамкой вокруг шапки участника (по живому показу).
      if (box.ink != DiagramInk.plate) {
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.stroke
            ..color = style.edge,
        );
      }

      return;
    }

    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.stroke
        ..color = style.colorOf(box.ink),
    );
  }

  /// Фигура узла: заливка и обводка — те же, что у коробки.
  void _figure(Canvas canvas, DiagramFigure figure) {
    if (figure.filled && !figure.outlined) {
      canvas.drawPath(figure.path, Paint()..color = style.colorOf(figure.ink));

      return;
    }
    if (figure.filled) {
      canvas
        ..drawPath(figure.path, Paint()..color = style.colorOf(figure.ink))
        ..drawPath(
          figure.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.stroke
            ..color = style.edge,
        );

      return;
    }

    canvas.drawPath(
      figure.path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.stroke
        ..color = style.colorOf(figure.ink),
    );
  }

  void _path(Canvas canvas, DiagramPath path) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          // Линия вызова толще прочих: она главная. Толстая — ещё толще:
          // в графе её так и просят написать, `==>`.
          ..strokeWidth =
              path.thick ? style.arrowStroke * 2 : (path.ink == DiagramInk.line ? style.arrowStroke : style.stroke)
          ..color = style.colorOf(path.ink);

    if (path.smooth) {
      _curve(canvas, path, paint);
    } else {
      for (var i = 0; i + 1 < path.points.length; i++) {
        final a = path.points[i];
        final b = path.points[i + 1];
        if (path.dashed) {
          _dashed(canvas, a, b, paint);
        } else {
          canvas.drawLine(a, b, paint);
        }
      }
    }

    if (path.head != DiagramHead.none && path.points.length >= 2) {
      _head(canvas, path.points[path.points.length - 2], path.points.last, path.head, paint);
    }
    if (path.tail != DiagramHead.none && path.points.length >= 2) {
      _head(canvas, path.points[1], path.points.first, path.tail, paint);
    }
  }

  /// Сглаженная кривая; пунктир — вдоль её длины, теми же штрихами, что у
  /// прямой.
  void _curve(Canvas canvas, DiagramPath path, Paint paint) {
    final curve = diagramBasis(path.points);
    if (curve.isEmpty) {
      return;
    }
    final line = Path()..moveTo(curve.first.from.dx, curve.first.from.dy);
    for (final cubic in curve) {
      line.cubicTo(cubic.c1.dx, cubic.c1.dy, cubic.c2.dx, cubic.c2.dy, cubic.to.dx, cubic.to.dy);
    }

    if (!path.dashed) {
      canvas.drawPath(line, paint);

      return;
    }

    const dash = 4.0;
    const gap = 4.0;
    for (final metric in line.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        canvas.drawPath(metric.extractPath(at, math.min(at + dash, metric.length)), paint);
      }
    }
  }

  /// Пунктир вручную: у `Canvas` его нет.
  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) {
      return;
    }
    final step = (b - a) / total;

    for (var at = 0.0; at < total; at += dash + gap) {
      final end = math.min(at + dash, total);
      canvas.drawLine(a + step * at, a + step * end, paint);
    }
  }

  void _head(Canvas canvas, Offset from, Offset to, DiagramHead head, Paint line) {
    final direction = to - from;
    if (direction.distance == 0) {
      return;
    }
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    const size = 6.0;

    switch (head) {
      case DiagramHead.none:
        return;

      case DiagramHead.arrow:
        final path =
            Path()
              ..moveTo(to.dx, to.dy)
              ..lineTo(to.dx - unit.dx * size + normal.dx * size / 2, to.dy - unit.dy * size + normal.dy * size / 2)
              ..lineTo(to.dx - unit.dx * size - normal.dx * size / 2, to.dy - unit.dy * size - normal.dy * size / 2)
              ..close();
        canvas.drawPath(path, Paint()..color = line.color);

      case DiagramHead.open:
        canvas
          ..drawLine(to, to - unit * size + normal * size / 2, line)
          ..drawLine(to, to - unit * size - normal * size / 2, line);

      case DiagramHead.cross:
        final half = size / 2;
        canvas
          ..drawLine(to - unit * half + normal * half, to + unit * half - normal * half, line)
          ..drawLine(to - unit * half - normal * half, to + unit * half + normal * half, line);

      case DiagramHead.circle:
        // Пустой внутри: залитый читался бы точкой на линии, а не её концом.
        canvas
          ..drawCircle(to - unit * (size / 3), size / 3, Paint()..color = style.background)
          ..drawCircle(to - unit * (size / 3), size / 3, line);

      // Кардинальность ER: знаки стоят на линии у самой рамки, ближний к ней
      // — «сколько больше всего», дальний — «сколько меньше всего», как в
      // нотации crow's foot (`docs/spec/mermaid.md`, §7а).
      case DiagramHead.exactlyOne:
        _bar(canvas, to - unit * 5, normal, line);
        _bar(canvas, to - unit * 9, normal, line);

      case DiagramHead.zeroOrOne:
        _bar(canvas, to - unit * 5, normal, line);
        _ring(canvas, to - unit * 12, line);

      case DiagramHead.oneOrMore:
        _foot(canvas, to, unit, normal, line);
        _bar(canvas, to - unit * 12, normal, line);

      case DiagramHead.zeroOrMore:
        _foot(canvas, to, unit, normal, line);
        _ring(canvas, to - unit * 15, line);
    }
  }

  /// Длина «лапки» вдоль линии и её полуразмах.
  static const double _footLength = 9;
  static const double _footSpread = 5;

  /// Поперечная черта.
  void _bar(Canvas canvas, Offset at, Offset normal, Paint line) =>
      canvas.drawLine(at + normal * _footSpread, at - normal * _footSpread, line);

  /// Пустой кружок на подложке фона: залитый читался бы точкой.
  void _ring(Canvas canvas, Offset at, Paint line) {
    const radius = 3.5;
    canvas
      ..drawCircle(at, radius, Paint()..color = style.background)
      ..drawCircle(at, radius, line);
  }

  /// «Воронья лапка»: три пальца от точки на линии к рамке.
  void _foot(Canvas canvas, Offset to, Offset unit, Offset normal, Paint line) {
    final heel = to - unit * _footLength;
    canvas
      ..drawLine(heel, to + normal * _footSpread, line)
      ..drawLine(heel, to, line)
      ..drawLine(heel, to - normal * _footSpread, line);
  }

  @override
  bool shouldRepaint(DiagramPainter old) => old.layout != layout || old.style != style;
}
