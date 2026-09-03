import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/function_bar/function_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Клавиши экрана доходят до команд, а не тонут в тексте.
///
/// Редактор — единственный экран, который забирает клавиатуру себе целиком:
/// печатать надо в текст. Поэтому важно, что то немногое, что принадлежит
/// экрану, он отпускает, — иначе человек остаётся в редакторе без выхода.
void main() {
  late AppRuntime runtime;
  late InMemoryContentProvider disk;

  setUp(() async {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/notes.txt', content: utf8.encode('раз\nдва\nтри')),
      // Файл длиннее экрана: на нём видно, что страница листается.
      FakeEntry.file('/home/long.txt', content: utf8.encode(List.generate(500, (i) => 'строка $i').join('\n'))),
    ])..home = '/home';
    runtime = await testApp(provider: disk, modules: featureModules());
    await runtime.app.start();
  });

  Future<EditorScreen> openEditor(WidgetTester tester, {String name = 'notes.txt'}) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.app.left.setCursorToName(name);
    await tester.runCommand(runtime.commands.create(EditFileCommand.commandId)!);

    return runtime.app.view.contentAt(ViewportPosition.fullscreen)! as EditorScreen;
  }

  Future<String> contentOf(String path) async {
    final node = (await disk.resolvePath().run(path))!;
    final chunks = await (await disk.openRead(node)).toList();
    return utf8.decode(chunks.expand((chunk) => chunk).toList());
  }

  testWidgets(
    'Esc закрывает редактор, а не тонет в нём',
    (tester) async => withDesktopPlatform(() async {
      await openEditor(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(runtime.app.view.contentAt(ViewportPosition.fullscreen), isNull);

      // И приложение по-прежнему слышит клавиатуру: фокус вернулся.
      final wasActive = runtime.app.activePanel;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(runtime.app.activePanel, isNot(same(wasActive)), reason: 'приложение оглохло после редактора');
      await disposeScreen(tester);
    }),
  );

  testWidgets(
    'F2 сохраняет, а не переносит строки',
    (tester) async => withDesktopPlatform(() async {
      final screen = await openEditor(tester);
      screen.controller.text = 'новое содержимое';
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();

      // Запись — единственное необратимое действие редактора, и она
      // спрашивает: `Enter` в окне соглашается. Ищем именно окно: «Save»
      // подписана и кнопка `F2` в ряду внизу.
      expect(runtime.app.view.dialogs.single.title, 'Save changes');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(await contentOf('/home/notes.txt'), 'новое содержимое');
      expect(screen.modified, isFalse);
      await disposeScreen(tester);
    }),
  );

  testWidgets(
    'F2 загорается, как только появилось несохранённое',
    (tester) async => withDesktopPlatform(() async {
      // Живая проверка показала обратное: правку сделали, а кнопка осталась
      // приглушённой — ряд подписан на стопку экранов и о правке не узнавал.
      final screen = await openEditor(tester);

      FunctionButton save() =>
          tester.widget<FunctionButton>(find.byWidgetPredicate((w) => w is FunctionButton && w.number == 2));

      expect(save().label, 'Save');
      expect(save().enabled, isFalse, reason: 'сохранять нечего: файл только открыли');

      screen.controller.text = 'правка';
      await tester.pump();

      expect(save().enabled, isTrue);
      await disposeScreen(tester);
    }),
  );

  testWidgets(
    'PgDn и PgUp листают текст',
    (tester) async => withDesktopPlatform(() async {
      // В библиотеке страница вверх и вниз не назначены ни на одну клавишу —
      // клавиши им даёт `FcTextShortcuts`. А ещё их должно хватать до текста:
      // в панелях за теми же клавишами стоят свои команды.
      final screen = await openEditor(tester, name: 'long.txt');
      expect(screen.controller.selection.baseIndex, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      final afterDown = screen.controller.selection.baseIndex;

      // Страница, а не строка: на экране умещается заметно больше одной.
      expect(afterDown, greaterThan(5), reason: 'PgDn не долистала');

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();

      expect(screen.controller.selection.baseIndex, lessThan(afterDown));
      await disposeScreen(tester);
    }),
  );

  testWidgets(
    'фокус сразу в тексте: курсор доступен без щелчка мышью',
    (tester) async => withDesktopPlatform(() async {
      // Печатать надо в текст, и просить об этом мышью человек не обязан.
      // Проверяется именно фокус, а не сама печать: ввод у `re_editor` идёт
      // через свой `TextInputClient`, и `tester.enterText` до него не достаёт —
      // он ищет `EditableText`, которого здесь нет.
      await openEditor(tester);

      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));

      expect(editor.focusNode?.hasFocus, isTrue);
      await disposeScreen(tester);
    }),
  );
}
