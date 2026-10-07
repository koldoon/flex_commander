import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Полоса хода работы как в macOS (`docs/spec/progress-bar.md`).
void main() {
  // Одна на все сборки: новая тема — это плавное перекрашивание
  // (`AnimatedTheme`), и его кадры выдавали бы себя за бег полосы.
  final theme = ThemeData(
    extensions: [
      FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
    ],
  );

  Future<void> pump(WidgetTester tester, Widget bar, {bool intrinsic = false}) => tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child:
                intrinsic
                    // Окно команды меряет себя по содержимому — полоса обязана
                    // это пережить.
                    ? IntrinsicWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [bar]))
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [bar]),
          ),
        ),
      ),
    ),
  );

  tearDown(() => FcProgressBar.debugStill = false);

  testWidgets('высота — метрика темы, ширина — вся отведённая', (tester) async {
    await pump(tester, const FcProgressBar(value: 0.4));

    final size = tester.getSize(find.byType(FcProgressBar));
    expect(size.height, const DefaultMetrics().progressHeight);
    expect(size.width, 400);
  });

  testWidgets('с долей не анимируется', (tester) async {
    await pump(tester, const FcProgressBar(value: 0.4));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('без доли бежит, а доля останавливает бег', (tester) async {
    await pump(tester, const FcProgressBar());
    expect(tester.hasRunningAnimations, isTrue);

    await pump(tester, const FcProgressBar(value: 0.5));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('debugStill — отрезок стоит, и pumpAndSettle доживает', (tester) async {
    FcProgressBar.debugStill = true;
    await pump(tester, const FcProgressBar());

    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('в окне, которое меряет себя по содержимому, не падает', (tester) async {
    await pump(tester, const FcProgressBar(value: 0.3), intrinsic: true);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FcProgressBar)).height, const DefaultMetrics().progressHeight);
  });
}
