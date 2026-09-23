import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Мини-пара панелей: где показан набор (`docs/spec/panel-sessions.md`, §3).
void main() {
  const metrics = DefaultMetrics();
  const colors = DefaultColors();
  const leftKey = Key('left');
  const rightKey = Key('right');

  Future<void> pump(WidgetTester tester, {required bool left, required bool right}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [FcTheme(colors: colors, metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts())],
        ),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [FcTheme(colors: colors, metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts())],
        ),
        home: Scaffold(
          body: Center(child: FcSideMarks(left: left, right: right, leftKey: leftKey, rightKey: rightKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('горит та сторона, где набор показан', (tester) async {
    await pump(tester, left: true, right: false);
    expect(find.byKey(leftKey), findsOneWidget);
    expect(find.byKey(rightKey), findsNothing, reason: 'ключ достаётся только горящей ячейке');

    await pump(tester, left: false, right: true);
    expect(find.byKey(leftKey), findsNothing);
    expect(find.byKey(rightKey), findsOneWidget);

    await pump(tester, left: true, right: true);
    expect(find.byKey(leftKey), findsOneWidget);
    expect(find.byKey(rightKey), findsOneWidget);
  });

  testWidgets('погасшая ячейка не пропадает, а темнеет', (tester) async {
    // Пара читается как две панели: одна ячейка вместо двух означала бы другое.
    await pump(tester, left: true, right: false);

    // Внутри самой пары: `Scaffold` рисует свои заливки, и общий поиск нашёл бы
    // их тоже.
    final cells =
        tester
            .widgetList<ColoredBox>(find.descendant(of: find.byType(FcSideMarks), matching: find.byType(ColoredBox)))
            .toList();
    expect(cells, hasLength(2));
    expect(cells.map((cell) => cell.color), [colors.markedBar, colors.panelBorder]);
  });

  testWidgets('ширина меряется тем же, чем рисуется', (tester) async {
    // По этому числу ряд наборов раздаёт место записям — разойтись им негде.
    await pump(tester, left: true, right: true);

    expect(
      tester.getSize(find.byType(FcSideMarks)).width,
      closeTo(
        FcSideMarks.widthOf(FcTheme(colors: colors, metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts())),
        0.5,
      ),
    );
  });
}
