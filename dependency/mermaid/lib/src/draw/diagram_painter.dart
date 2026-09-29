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
        case DiagramPath():
          _path(canvas, shape);
        case DiagramLabel(:final run, :final at):
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
          ..color = style.edge,
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

  void _path(Canvas canvas, DiagramPath path) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.stroke
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
    }
  }

  @override
  bool shouldRepaint(DiagramPainter old) => old.layout != layout || old.style != style;
}
