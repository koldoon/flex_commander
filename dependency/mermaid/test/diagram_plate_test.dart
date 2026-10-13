import 'dart:ui' as ui;

import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_mermaid/src/draw/diagram_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Плашка участника — без обводки (`docs/spec/mermaid.md`, §9).
///
/// Цвет плашки бывает полупрозрачным (вторичный текст в оформлениях macOS), и
/// обводка того же цвета поверх заливки давала край светлее середины — рамку.
void main() {
  testWidgets('край полупрозрачной плашки — того же цвета, что середина', (tester) async {
    const style = DiagramStyle(
      text: {},
      line: Color(0xFFFFFFFF),
      fill: Color(0xFF000000),
      edge: Color(0xFFFFFFFF),
      bar: Color(0xFF000000),
      faint: Color(0xFF000000),
      divider: Color(0xFF000000),
      plate: Color(0x80FFFFFF),
      onPlate: Color(0xFF000000),
      background: Color(0xFF000000),
      stroke: 2,
    );
    const layout = DiagramLayout(
      size: Size(60, 40),
      shapes: [DiagramBox(rect: Rect.fromLTWH(10, 10, 40, 20), ink: DiagramInk.plate)],
    );

    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, 60, 40), Paint()..color = style.background);
      const DiagramPainter(layout: layout, style: style).paint(canvas, layout.size);
      final image = await recorder.endRecording().toImage(60, 40);

      return (await image.toByteData())!;
    });

    int red(int x, int y) => bytes!.getUint8((y * 60 + x) * 4);

    expect(red(10, 20), red(30, 20), reason: 'край не светлее середины — рамки нет');
  });
}
