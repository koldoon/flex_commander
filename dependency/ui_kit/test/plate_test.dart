import 'dart:ui' as ui;

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Плашка: поле внутри — тексту, вплотную — списку
/// (`docs/spec/settings-presets.md`).
void main() {
  final boundary = GlobalKey();

  Future<void> pumpPlate(WidgetTester tester, {required bool tight}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 100);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Material(
          color: const DefaultColors().dialogBackground,
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 120,
                child: FcPlate(
                  tight: tight,
                  // Курсор первой строки — во всю ширину, как в дереве.
                  child: Container(height: 40, color: const DefaultColors().cursorBackground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Точки нарисованной плашки.
  Future<List<int>> pixels(WidgetTester tester) async {
    final bytes = await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  testWidgets('курсор не ложится на скруглённый угол', (tester) async {
    await pumpPlate(tester, tight: true);

    final data = await pixels(tester);
    final width = tester.getSize(find.byKey(boundary)).width.round();
    (int, int, int) at(int x, int y) {
      final i = (y * width + x) * 4;
      return (data[i], data[i + 1], data[i + 2]);
    }

    final cursor = const DefaultColors().cursorBackground;
    final expected = ((cursor.r * 255).round(), (cursor.g * 255).round(), (cursor.b * 255).round());

    // У самого скругления — не курсор: обрезка идёт по **внутреннему** краю
    // плашки, и угол остаётся за обводкой. По внешнему краю курсор доходил до
    // кромки и ложился на скругление сверху — ровно в этих точках.
    expect(at(2, 1), isNot(expected));
    expect(at(1, 2), isNot(expected));
    // А посередине — он самый: курсор идёт во всю ширину.
    expect(at(width ~/ 2, 20), expected);
  });
}
