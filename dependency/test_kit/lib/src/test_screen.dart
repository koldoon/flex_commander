import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поднимает экран в дереве виджетов: тема, область приложения и сам экран.
///
/// Экран собирается тем же вызовом, что и в приложении (`Screen.build`), —
/// иначе тест проверял бы не то, что показывают.
Future<void> pumpScreen(WidgetTester tester, Screen screen, {Application? app}) async {
  Widget content = Builder(builder: screen.build);
  if (app != null) {
    content = AppScope(controller: app, child: content);
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: const [
          FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
        ],
      ),
      home: Scaffold(body: content),
    ),
  );
  await tester.pump();
}

/// Разбирает дерево после теста.
///
/// Обязателен там, где показан текст: курсор в нём моргает по таймеру, пока
/// поле в фокусе, а `flutter_test` считает незакрытый таймер ошибкой. Пауза
/// перед разбором — чтобы успели сработать отложенные задачи самого поля.
Future<void> disposeScreen(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}
