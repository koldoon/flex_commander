import 'dart:ui' as ui;

import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_mermaid/src/draw/diagram_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Знаки кардинальности ER на конце линии (`docs/spec/mermaid.md`, §7а).
///
/// По пикселям: линия идёт по горизонтали к точке `to`, и знак виден как мазки
/// **поперёк** неё — выше и ниже оси, — на своём расстоянии от конца.
void main() {
  const style = DiagramStyle(
    text: {},
    line: Color(0xFFFFFFFF),
    fill: Color(0xFF000000),
    edge: Color(0xFF000000),
    bar: Color(0xFF000000),
    faint: Color(0xFF000000),
    plate: Color(0xFF000000),
    onPlate: Color(0xFF000000),
    background: Color(0xFF000000),
    stroke: 1,
  );

  const axis = 20.0;
  const end = 100.0;

  /// Нарисовать линию с [head] у правого конца; вернуть, где поперёк оси есть
  /// мазки: расстояния от конца, на которых хоть одна точка на 4 выше или ниже
  /// оси светлая.
  Future<Set<int>> marksOf(WidgetTester tester, DiagramHead head) async {
    final layout = DiagramLayout(
      size: const Size(120, 40),
      shapes: [
        DiagramPath(points: const [Offset(10, axis), Offset(end, axis)], head: head),
      ],
    );

    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, 120, 40), Paint()..color = style.background);
      DiagramPainter(layout: layout, style: style).paint(canvas, layout.size);
      final image = await recorder.endRecording().toImage(120, 40);

      return (await image.toByteData())!;
    });

    bool lit(int x, int y) => bytes!.getUint8((y * 120 + x) * 4) > 100;

    return {
      for (var back = 0; back <= 20; back++)
        if (lit((end - back).round(), (axis - 4).round()) || lit((end - back).round(), (axis + 4).round())) back,
    };
  }

  testWidgets('без знака поперёк линии пусто', (tester) async {
    expect(await marksOf(tester, DiagramHead.none), isEmpty);
  });

  testWidgets('«ровно один» — две черты у самого конца', (tester) async {
    final marks = await marksOf(tester, DiagramHead.exactlyOne);

    expect(marks, containsAll([5, 9]));
    expect(marks.any((back) => back > 11), isFalse, reason: 'дальше черт — ничего');
  });

  testWidgets('«ноль или один» — черта у конца и кружок дальше', (tester) async {
    final marks = await marksOf(tester, DiagramHead.zeroOrOne);

    expect(marks, contains(5));
    expect(marks.any((back) => back >= 10 && back <= 14), isTrue, reason: 'кружок');
  });

  testWidgets('«один или много» — лапка у конца и черта за ней', (tester) async {
    final marks = await marksOf(tester, DiagramHead.oneOrMore);

    expect(marks.any((back) => back <= 3), isTrue, reason: 'пальцы лапки расходятся к самому концу');
    expect(marks, contains(12));
  });

  testWidgets('«ноль или много» — лапка у конца и кружок за ней', (tester) async {
    final marks = await marksOf(tester, DiagramHead.zeroOrMore);

    expect(marks.any((back) => back <= 3), isTrue, reason: 'лапка');
    expect(marks.any((back) => back >= 13 && back <= 17), isTrue, reason: 'кружок');
  });
}
