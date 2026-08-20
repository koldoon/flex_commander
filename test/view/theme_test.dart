import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:flex_commander/state/theme_controller.dart';
import 'package:flex_commander/view/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оформление взято у референсного приложения. Здесь закреплено то, что при
/// правках легко потерять молча: палитра, шрифты и кегль.
/// Оформление по умолчанию: значения приносит модуль темы, API описывает роли.
const defaultThemeSpec = FcThemeSpec(
  id: 'default',
  title: 'Default',
  colors: DefaultColors(),
  metrics: DefaultMetrics(),
  icons: DefaultIcons(),
  fonts: DefaultFonts(),
);

void main() {
  test('оформление по умолчанию — тёмное, как у референса', () {
    final theme = buildThemeData(defaultThemeSpec);

    expect(theme.brightness, Brightness.dark);
    expect(theme.extension<FcTheme>(), isNotNull);
  });

  group('смена оформления', () {
    testWidgets('приложение перерисовывается по выбору темы', (tester) async {
      final themes = ThemeController([
        defaultThemeSpec,
        const FcThemeSpec(
          id: 'light',
          title: 'Light',
          brightness: Brightness.light,
          colors: DefaultColors(),
          metrics: DefaultMetrics(),
          icons: DefaultIcons(),
          fonts: DefaultFonts(),
        ),
      ]);

      await tester.pumpWidget(
        ListenableBuilder(
          listenable: themes,
          builder:
              (context, _) => MaterialApp(
                theme: buildThemeData(themes.current),
                home: Builder(builder: (context) => Text('${Theme.of(context).brightness}')),
              ),
        ),
      );
      expect(find.text('Brightness.dark'), findsOneWidget);

      themes.use('light');
      // MaterialApp переводит тему анимацией, поэтому одного кадра мало.
      await tester.pumpAndSettle();

      expect(find.text('Brightness.light'), findsOneWidget);
    });
  });
}
