import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_commander/view/split_view.dart';

/// Разделитель панелей: он обязан идти ровно за курсором.
void main() {
  const double width = 800;
  const metrics = DefaultMetrics();
  final double available = width - metrics.panelGap;

  double? reported;

  Future<void> pump(WidgetTester tester, {double ratio = 0.5}) async {
    reported = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 400,
              child: SplitView(
                left: const ColoredBox(color: Color(0xFF001122)),
                right: const ColoredBox(color: Color(0xFF112233)),
                ratio: ratio,
                onRatioChanged: (value) => reported = value,
                onCenter: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Точка захвата: середина зазора между панелями.
  Offset handleOf(WidgetTester tester, double ratio) {
    final split = tester.getRect(find.byType(SplitView));
    return Offset(split.left + available * ratio + metrics.panelGap / 2, split.center.dy);
  }

  /// Берётся за разделитель и преодолевает порог, с которого перетаскивание
  /// вообще считается перетаскиванием: это движение уходит на распознавание, и
  /// доля от него не меняется.
  Future<TestGesture> startDrag(WidgetTester tester, {double offset = 0}) async {
    final gesture = await tester.startGesture(handleOf(tester, 0.5) + Offset(offset, 0));
    await gesture.moveBy(const Offset(kDragSlopDefault + 1, 0));
    return gesture;
  }

  testWidgets('несколько движений за один кадр доходят все', (tester) async {
    // Смещения курсора приходят чаще, чем рисуются кадры. Пока доля считалась
    // из них, все пришедшие за кадр считались от одной и той же ширины — и
    // уцелевало только последнее: разделитель отставал от курсора.
    await pump(tester);

    final gesture = await startDrag(tester);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(reported, closeTo(0.5 + 80 / available, 0.001));
  });

  testWidgets('движение влево так же точно', (tester) async {
    await pump(tester);

    final gesture = await startDrag(tester);
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(reported, closeTo(0.5 - 60 / available, 0.001));
  });

  testWidgets('взялись не по центру — разделитель не прыгает', (tester) async {
    await pump(tester);

    // За разделитель берутся где придётся: он узкий, а область захвата шире.
    final gesture = await startDrag(tester, offset: 3);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    // Доля изменилась ровно на пройденное, а не подскочила на те три точки,
    // на которые промахнулись мимо середины.
    expect(reported, closeTo(0.5 + 20 / available, 0.001));
  });
}
