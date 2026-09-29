import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.stroke
          // У плашки обводка того же цвета, что заливка: отдельная граница
          // разрезала бы её пополам.
          ..color = box.ink == DiagramInk.plate ? style.plate : style.edge,
      );

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

    for (var i = 0; i + 1 < path.points.length; i++) {
      final a = path.points[i];
      final b = path.points[i + 1];
      if (path.dashed) {
        _dashed(canvas, a, b, paint);
      } else {
        canvas.drawLine(a, b, paint);
      }
    }

    if (path.head != DiagramHead.none && path.points.length >= 2) {
      _head(canvas, path.points[path.points.length - 2], path.points.last, path.head, paint);
    }
    if (path.tail != DiagramHead.none && path.points.length >= 2) {
      _head(canvas, path.points[1], path.points.first, path.tail, paint);
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
    }
  }

  @override
  bool shouldRepaint(DiagramPainter old) => old.layout != layout || old.style != style;
}
