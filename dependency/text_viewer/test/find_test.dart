import 'dart:convert';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поиск по тексту в просмотрщике.
///
/// Панели поиска у нас нет: строку спрашивает окно команды, найденное
/// подсвечивает сам показ, а счёт совпадений уходит всплывающим сообщением.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file(
          '/home/notes.txt',
          content: utf8.encode('первая строка\nвторая строка\nтретья строка\nПервая снова'),
        ),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  /// Запускает команду и **дожидается** её: поиск считается в изоляте, а
  /// `commands.run` возвращает управление сразу.
  Future<void> runCommand(String id, [Map<String, Object?> parameters = const {}]) async {
    final AppCommand command = runtime.commands.create(id)!;
    await command.executeWith(parameters);
  }

  Future<TextViewerScreen> openViewer() async {
    runtime.app.left.setCursorToName('notes.txt');
    await (runtime.commands.create(ViewFileCommand.commandId)!).executeWith();
    return runtime.app.view.contentAt(ViewportPosition.fullscreen)! as TextViewerScreen;
  }

  group('клавиши', () {
    test('F7 и Cmd-F ищут, а в панелях за F7 стоит своё', () async {
      // В панелях F7 — создание каталога. Привязки принадлежат экрану, и это
      // тот случай, ради которого `KeyBinding.screen` заводился.
      expect(runtime.commands.commandFor(KeyCombination.parse('F7'))?.id, isNot(TextViewer.findCommandId));

      await openViewer();

      expect(runtime.commands.commandFor(KeyCombination.parse('F7'))?.id, TextViewer.findCommandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Cmd-F'))?.id, TextViewer.findCommandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Shift-F7'))?.id, TextViewer.findNextCommandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Cmd-G'))?.id, TextViewer.findNextCommandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Shift-Cmd-G'))?.id, TextViewer.findPreviousCommandId);
    });

    test('пока не искали, ходить не по чему', () async {
      await openViewer();

      final next = runtime.commands.find(TextViewer.findNextCommandId)!;
      expect(runtime.commands.isExecutable(next), isFalse);
    });
  });

  group('поиск', () {
    test('находит, выделяет и говорит счёт', () async {
      final screen = await openViewer();

      await runCommand(TextViewer.findCommandId, {FcFindTextCommand.patternParam: 'строка'});

      expect(screen.finder.matchCount, 3);
      expect(screen.controller.selectedText, 'строка');
      expect(runtime.app.toasts.current?.message, 'Match 1 of 3');
    });

    test('следующее идёт по кругу и тоже говорит счёт', () async {
      final screen = await openViewer();
      await runCommand(TextViewer.findCommandId, {FcFindTextCommand.patternParam: 'строка'});

      await runCommand(TextViewer.findNextCommandId);
      expect(screen.finder.currentIndex, 2);
      expect(runtime.app.toasts.current?.message, 'Match 2 of 3');

      await runCommand(TextViewer.findPreviousCommandId);
      expect(screen.finder.currentIndex, 1);
    });

    test('с учётом регистра ищет иначе', () async {
      final screen = await openViewer();

      await runCommand(TextViewer.findCommandId, {
        FcFindTextCommand.patternParam: 'первая',
        FcFindTextCommand.caseSensitiveParam: true,
      });

      expect(screen.finder.matchCount, 1);
    });

    test('не нашлось — сказано прямо', () async {
      await openViewer();

      await runCommand(TextViewer.findCommandId, {FcFindTextCommand.patternParam: 'кошка'});

      expect(runtime.app.toasts.current?.message, 'Not found: кошка');
    });
  });

  group('окно', () {
    // Искать внутри виджетного теста нельзя: поиск считается в изоляте, а
    // `flutter_test` живёт на поддельном времени — ответа оттуда не дождаться,
    // и прогон висит до таймаута. Поэтому здесь только то, что не ищет, а сам
    // поиск проверяется выше, обычными тестами. См. docs/screens.md.
    testWidgets(
      'F7 открывает окно с полем ввода',
      (tester) async => withDesktopPlatform(() async {
        await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
        await tester.pump();
        await openViewer();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        runtime.commands.dispatch(KeyCombination.parse('F7'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(dialogField(), findsOneWidget);
        // Прошлой строки ещё не было — поле пустое и ждёт набора.
        expect(tester.widget<TextField>(dialogField()).controller?.text, isEmpty);
        expect(find.text('Case sensitive'), findsOneWidget);
        expect(find.text('Regular expression'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await disposeScreen(tester);
      }),
    );
  });

  group('окно не закрывается, пока не нашлось', () {
    test('не нашлось — ошибка в окне, а не закрытие', () async {
      final screen = await openViewer();
      final state = FcFindDialogState(
        finder: screen.finder,
        pattern: 'кошка',
        caseSensitive: false,
        regex: false,
        onFound: () => runtime.app.toasts.show('Match 1 of 3'),
      );

      await state.submit();

      // Строку правят тут же, а не набирают заново из-за одной опечатки.
      expect(state.error, 'Not found: кошка');
    });

    test('нашлось — ошибки нет, счёт сказан', () async {
      final screen = await openViewer();
      final state = FcFindDialogState(
        finder: screen.finder,
        pattern: 'строка',
        caseSensitive: false,
        regex: false,
        onFound: () => runtime.app.toasts.show('Match 1 of 3'),
      );

      await state.submit();

      expect(state.error, isNull);
      expect(screen.finder.matchCount, 3);
      expect(runtime.app.toasts.current?.message, 'Match 1 of 3');
    });

    test('пустая строка — вопрос к вводу, а не поиск', () async {
      final screen = await openViewer();
      final state = FcFindDialogState(
        finder: screen.finder,
        pattern: '',
        caseSensitive: false,
        regex: false,
        onFound: () => runtime.app.toasts.show('Match 1 of 3'),
      );

      await state.submit();

      expect(state.error, 'Nothing to find');
    });

    test('негодное выражение названо негодным', () async {
      final screen = await openViewer();
      final state = FcFindDialogState(
        finder: screen.finder,
        pattern: '(',
        caseSensitive: false,
        regex: true,
        onFound: () {},
      );

      await state.submit();

      expect(state.error, 'Not a valid expression');
    });
  });
}
