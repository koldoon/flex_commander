import 'dart:convert';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Выделение и копирование в буфер обмена.
///
/// Выделяет человек мышью или клавишами — этим занимается сам показ, — а
/// копирует команда просмотрщика: она проходит через буфер обмена приложения и
/// говорит, что случилось.
void main() {
  late AppRuntime runtime;
  late FakeClipboard clipboard;

  setUp(() async {
    clipboard = FakeClipboard();
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('первая строка\nвторая строка\nтретья строка')),
      ])..home = '/home',
      modules: featureModules(),
      clipboard: clipboard,
    );
    await runtime.app.start();
  });

  Future<TextViewerScreen> openViewer() async {
    runtime.app.left.setCursorToName('notes.txt');
    await (runtime.commands.create(ViewFileCommand.commandId)!).executeWith();
    return runtime.app.view.contentAt(ViewportPosition.fullscreen)! as TextViewerScreen;
  }

  test('пока ничего не выделено, копировать нечего', () async {
    await openViewer();

    final copy = runtime.commands.find(CopySelectionCommand.commandId)!;

    // Кнопка в ряду останется приглушённой, а не сделает вид, что сработала.
    expect(runtime.commands.isExecutable(copy), isFalse);
  });

  test('выделенное уходит в буфер по Cmd-C', () async {
    final screen = await openViewer();
    screen.controller.selectLine(1);

    expect(runtime.commands.dispatch(KeyCombination.parse('Cmd-C')), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(clipboard.text, contains('вторая строка'));
    // Случилось и закончилось — о таком говорят всплывающим сообщением.
    expect(runtime.app.toasts.current?.message, contains('Copied'));
  });

  test('снятое выделение снова делает копирование недоступным', () async {
    final screen = await openViewer();
    screen.controller.selectLine(0);
    expect(screen.hasSelection, isTrue);

    screen.controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);

    expect(screen.hasSelection, isFalse);
    expect(runtime.commands.isExecutable(runtime.commands.find(CopySelectionCommand.commandId)!), isFalse);
  });

  test('в панелях Cmd-C просмотрщику не принадлежит', () {
    expect(runtime.commands.commandFor(KeyCombination.parse('Cmd-C'))?.id, isNot(CopySelectionCommand.commandId));
  });

  testWidgets(
    'копирование отпущено команде, а не виджету',
    (tester) async => withDesktopPlatform(() async {
      // Иначе `Cmd-C` сработала бы дважды: своя команда и встроенное сочетание.
      // Приложение собрано в `setUp`, то есть в настоящем времени, а тело
      // виджет-теста идёт в поддельном. Чтение содержимого — разговор с ядром,
      // и ждать его надо там, где оно на самом деле идёт.
      final screen = (await tester.runAsync(openViewer))!;
      await pumpScreen(tester, TextViewerView(screen: screen), app: runtime.app);

      final view = tester.widget<FcTextView>(find.byType(FcTextView));

      expect(view.shortcuts.released, contains(CodeShortcutType.copy));
      await disposeScreen(tester);
    }),
  );
}
