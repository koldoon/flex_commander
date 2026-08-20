import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';
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

/// Выполняет тело теста так, будто приложение работает на настольной системе.
///
/// Без этого показ текста собирается **мобильной** веткой `re_editor`: в ней
/// нет `Shortcuts` вовсе, и ни одна клавиша до текста не доходит — ни стрелки,
/// ни страницы. В тестах платформа по умолчанию Android, а приложение живёт на
/// macOS, и проверять надо то, что поедет к людям.
///
/// Значение обязательно вернуть до конца тела теста: `flutter_test` считает
/// оставленную отладочную переменную ошибкой, и `tearDown` для этого уже
/// поздно.
///
/// **Оборачивать нужно каждый тест файла, а не только тот, что нажимает
/// клавиши.** Платформу `re_editor` вычисляет один раз на изолят, и первый же
/// собранный показ закрепляет её на весь файл: один необёрнутый тест в начале
/// — и клавиши не работают до конца прогона.
Future<void> withDesktopPlatform(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
