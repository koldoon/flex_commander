import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_modules.dart';

/// Строка показывает то приглашение, которое напечатала оболочка
/// (`docs/spec/shell-prompt.md`, §7).
void main() {
  late AppRuntime runtime;
  late FakePty pty;

  setUp(() async {
    pty = FakePty();
    runtime = await testApp(
      provider: InMemoryTreeProvider(
        [FakeEntry.directory('/home'), FakeEntry.directory('/home/work'), FakeEntry.file('/home/alpha.txt', size: 10)],
        null,
        pty,
      )..home = '/home',
      modules: modulesWithTerminal(),
    );
    await runtime.app.start();
  });

  /// Поднять приложение и завести оболочку: до первого `Ctrl-O` её нет вовсе.
  Future<AgreeingShell> open(WidgetTester tester, {String prompt = r'koldoon@cray /home % '}) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-O'));
    await tester.pumpAndSettle();

    final shell = AgreeingShell(pty.session, promptText: prompt);
    shell.greet();
    await tester.pump(TerminalSession.promptSettleDelay * 2);

    // Терминал убираем: смотрим на строку под панелями, а не на него.
    runtime.commands.dispatch(KeyCombination.parse('Ctrl-O'));
    await tester.pumpAndSettle();
    return shell;
  }

  CommandLineState lineState() => runtime.app.view.contentAt(ViewportPosition.bottom)! as CommandLineState;

  Finder promptText() => find.descendant(of: find.byType(CommandLineView), matching: find.byType(RichText));

  testWidgets('приглашение оболочки встаёт в строку вместо пути', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    expect(find.text('/home\$'), findsOneWidget, reason: 'пока оболочка молчит — своё приглашение');

    await open(tester);

    expect(find.text('/home\$'), findsNothing);
    expect(
      tester.widgetList<RichText>(promptText()).map((text) => text.text.toPlainText()),
      contains(r'koldoon@cray /home %'),
    );

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('выключенная настройка возвращает путь и доллар', (tester) async {
    await open(tester);

    lineState().settings.shellPrompt = false;
    // Перерисовку строке приносит панель: настройка читается на сборке, а
    // окно настроек, закрываясь, перерисовывает экран целиком.
    runtime.app.left.setCursorToName('alpha.txt');
    await tester.pumpAndSettle();

    expect(find.text('/home\$'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  /// Что ушло в оболочку после этой отметки.
  ///
  /// Отметкой, а не очисткой записей: в них лежит строка уговора, и по ней
  /// подставная оболочка узнаёт своё число — сотрёшь её, и оболочка замолчит.
  String sentSince(int mark) => pty.session.written.substring(mark);

  group('оболочка идёт за панелью', () {
    testWidgets('панель шагнула — cd ушёл, и с ведущим пробелом', (tester) async {
      final shell = await open(tester);
      final mark = pty.session.written.length;

      await runtime.app.left.openPath('/home/work');
      await tester.pumpAndSettle();

      expect(sentSince(mark), contains(' cd /home/work'), reason: 'служебный cd в историю не нужен');

      // Оболочка ответила приглашением оттуда — и панель осталась на месте:
      // это мы и просили.
      shell.directory = '/home/work';
      shell.promptText = r'/home/work % ';
      shell.greet();
      await tester.pump(TerminalSession.promptSettleDelay * 2);
      await tester.pumpAndSettle();

      expect(runtime.app.left.currentPath, '/home/work');

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('выключенная настройка ничего не шлёт', (tester) async {
      await open(tester);
      lineState().settings.shellFollowsPanel = false;
      final mark = pty.session.written.length;

      await runtime.app.left.openPath('/home/work');
      await tester.pumpAndSettle();

      expect(sentSince(mark), isNot(contains('cd ')), reason: 'ленивое поведение, как было');

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('пока команда идёт, cd ждёт приглашения', (tester) async {
      final shell = await open(tester);
      shell.start();
      await tester.pumpAndSettle();
      final mark = pty.session.written.length;

      await runtime.app.left.openPath('/home/work');
      await tester.pumpAndSettle();

      expect(sentSince(mark), isNot(contains('cd ')), reason: 'строка досталась бы самой команде');

      // Команда кончилась — оболочка освободилась, и просьба досылается.
      shell.finish();
      await tester.pump(TerminalSession.promptSettleDelay * 2);
      await tester.pumpAndSettle();

      expect(sentSince(mark), contains(' cd /home/work'));

      await tester.pump(const Duration(milliseconds: 20));
    });
  });
}
