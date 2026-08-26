import 'package:fc_api/fc_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_modules.dart';

/// Строка в собранном приложении: фокус, набор и то, что видно.
void main() {
  late AppRuntime runtime;
  late FakePty pty;

  setUp(() async {
    pty = FakePty();
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/alpha.txt', size: 10),
        FakeEntry.file('/home/beta.txt', size: 10),
      ])..home = '/home',
      modules: modulesWithTerminal(pty),
    );
    await runtime.app.start();
  });

  Finder lineField() => find.descendant(of: find.byType(CommandLineView), matching: find.byType(TextField));

  testWidgets('строка видна внизу и показывает каталог панели', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    expect(find.byType(CommandLineView), findsOneWidget);
    expect(find.text('/home\$'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('до Cmd-T буква ищет файл, после — попадает в поле', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    // Пока ввод у панели, печать — это переход к имени. Отнять её нельзя.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(runtime.app.left.currentNode?.name, 'beta.txt');

    runtime.commands.dispatch(KeyCombination.parse('Cmd-T'));
    await tester.pumpAndSettle();

    // Системный фокус пошёл следом за владельцем ввода.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'command line');

    await tester.enterText(lineField(), 'echo привет');
    await tester.pumpAndSettle();

    expect(find.text('echo привет'), findsOneWidget);
    // И курсор панели остался там, где стоял.
    expect(runtime.app.left.currentNode?.name, 'beta.txt');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('Enter на пустой строке ничего не ломает: курсор на месте', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Cmd-T'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Ни курсор не пропал, ни ввод не потерялся: и то и другое у строки.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'command line');
    expect(runtime.app.view.activeArea, ViewportPosition.bottom);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('фокус увели мимо нас — ввод возвращается панели', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Cmd-T'));
    await tester.pumpAndSettle();
    expect(runtime.app.view.activeArea, ViewportPosition.bottom);

    // `F7` из строки достаётся панели (функциональные — её), и окно забирает
    // фокус себе. Видимое состояние главнее: курсора в строке нет, значит и
    // ввода у неё нет.
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.pumpAndSettle();

    expect(dialogField(), findsWidgets);
    expect(runtime.app.view.activeArea, ViewportPosition.left);

    // Окно закрылось и вернуло фокус туда, откуда забрало, — в строку. Значит
    // и ввод сюда же: иначе курсор мигает, а клавиши работают панельные.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'command line');
    expect(runtime.app.view.activeArea, ViewportPosition.bottom);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('кандидаты видны над строкой и уходят от правки', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Cmd-T'));
    await tester.pumpAndSettle();

    await tester.enterText(lineField(), 'cat ');
    runtime.commands.dispatch(KeyCombination.parse('Tab'));
    await tester.pumpAndSettle();

    // Выбирать есть из чего — значит видно, из чего.
    expect(find.textContaining('alpha.txt'), findsWidgets);
    expect(find.textContaining('beta.txt'), findsWidgets);

    // Тронули строку — подсказка ушла: `Tab` после правки это новый подбор.
    await tester.enterText(lineField(), 'cat x');
    await tester.pumpAndSettle();
    expect(find.textContaining('beta.txt'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('щелчок мышью по строке отдаёт ей ввод', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    expect(runtime.app.view.activeArea, ViewportPosition.left);

    await tester.tap(lineField());
    await tester.pumpAndSettle();

    expect(runtime.app.view.activeArea, ViewportPosition.bottom);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('Esc возвращает ввод панели, и поиск по букве оживает', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Cmd-T'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Esc'));
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('command line'));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(runtime.app.left.currentNode?.name, 'alpha.txt');

    await tester.pump(const Duration(milliseconds: 20));
  });
}
