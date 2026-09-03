import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_modules.dart';

/// Режим `mc`: печать уходит в строку, а ввод остаётся у панели.
///
/// Главное, что здесь проверяется, — что режим **ничего не выключает вручную**.
/// Он меняет только выполнимость своих команд, а клавиша достаётся тому, кто
/// объявлен следом.
late AppRuntime runtime;
late TerminalSettings settings;

Application get app => runtime.app;

CommandLineState get line => app.view.contentAt(ViewportPosition.bottom)! as CommandLineState;

bool press(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

/// Набирает так, как это приходит с клавиатуры: имя клавиши в верхнем
/// регистре плюс символ, который дала раскладка.
void typeKeys(String value) {
  for (final char in value.split('')) {
    runtime.commands.dispatch(KeyCombination(char.toUpperCase(), character: char));
  }
}

void main() {
  final pty = FakePty();

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider(
        [
          FakeEntry.directory('/home'),
          FakeEntry.directory('/home/docs'),
          FakeEntry.file('/home/alpha.txt', size: 1),
          FakeEntry.file('/home/beta.txt', size: 1),
        ],
        null,
        pty,
      )..home = '/home',
      modules: modulesWithTerminal(),
    );
    await runtime.app.start();
    settings = line.settings;
  });

  group('настройка выключена', () {
    test('буква ведёт к имени, как раньше', () {
      expect(press('B'), isTrue);

      expect(app.left.currentEntry?.name, 'beta.txt');
      expect(line.text.text, isEmpty);
    });

    test('Enter входит в каталог, Bsp уводит вверх, Space помечает', () async {
      app.left.setCursorToName('docs');
      press('Enter');
      await pumpEventQueue();
      expect(app.left.path, '/home/docs');

      press('Bsp');
      await pumpEventQueue();
      expect(app.left.path, '/home');

      app.left.setCursorToName('alpha.txt');
      press('Space');
      expect(app.left.marked, contains('alpha.txt'));
    });
  });

  group('настройка включена', () {
    setUp(() => settings.typingGoesToLine = true);

    test('буква уходит в строку, а курсор панели стоит на месте', () {
      final before = app.left.currentEntry?.name;
      typeKeys('ls');

      expect(line.text.text, 'ls');
      expect(app.left.currentEntry?.name, before, reason: 'перехода к имени быть не должно');
    });

    test('пусто — клавиши панели, не пусто — строки', () async {
      // Пустая строка: панель работает как обычно.
      app.left.setCursorToName('alpha.txt');
      press('Space');
      expect(app.left.marked, contains('alpha.txt'));

      typeKeys('ls');
      // Теперь в строке что-то есть — те же клавиши достаются ей.
      press('Space');
      expect(line.text.text, 'ls ');

      press('Bsp');
      expect(line.text.text, 'ls');

      press('Esc');
      expect(line.text.text, isEmpty);

      // И снова панель: строка опять пуста.
      press('Bsp');
      await pumpEventQueue();
      expect(app.left.path, '/');
    });

    test('Enter выполняет набранное, а на пустой строке входит в каталог', () async {
      app.left.setCursorToName('docs');
      typeKeys('cd docs');
      press('Enter');
      await pumpEventQueue();

      // `cd` ведёт панель — значит она и переехала, а команда запомнилась.
      expect(app.left.path, '/home/docs');
      expect(line.history, ['cd docs']);
      expect(line.text.text, isEmpty);

      // Строка пуста — Enter снова панельный.
      await app.left.openPath('/home');
      app.left.setCursorToName('docs');
      press('Enter');
      await pumpEventQueue();
      expect(app.left.path, '/home/docs');
    });

    test('ввод остаётся у панели — стрелки и Tab по-прежнему её', () {
      typeKeys('ls');

      expect(app.view.activeArea, ViewportPosition.left);
      expect(runtime.commands.commandFor(KeyCombination.parse('Up'))?.id, 'panel.cursor.up');
      expect(runtime.commands.commandFor(KeyCombination.parse('Tab'))?.id, 'app.togglePanel');
      expect(runtime.commands.commandFor(KeyCombination.parse('F5')), isNotNull);
    });

    test('Cmd-T даёт полноценную строку с дополнением', () async {
      typeKeys('cat a');
      press('Cmd-T');

      expect(app.view.activeArea, ViewportPosition.bottom);
      // Дополнение вернулось вместе с вводом.
      press('Tab');
      await pumpEventQueue();
      expect(line.text.text, 'cat alpha.txt');

      press('Esc');
      expect(app.view.activeArea, ViewportPosition.left);
    });

    test('на источнике без настоящих путей печать по-прежнему ведёт к имени', () async {
      runtime = await testApp(
        // Без оболочки: `ShellHost` это дерево не объявляет.
        provider: InMemoryReadOnlyProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/beta.txt', size: 1)])
          ..home = '/home',
        modules: modulesWithTerminal(),
      );
      await runtime.app.start();
      line.settings.typingGoesToLine = true;

      expect(press('B'), isTrue);
      expect(app.left.currentEntry?.name, 'beta.txt');
      expect(line.text.text, isEmpty);
    });
  });

  test('настройка переключается командой и переживает перезапуск', () async {
    expect(settings.typingGoesToLine, isFalse);

    expect(runtime.commands.run('terminal.toggleTyping'), isTrue);
    await pumpEventQueue();
    expect(settings.typingGoesToLine, isTrue);

    runtime.commands.run('terminal.toggleTyping');
    await pumpEventQueue();
    expect(settings.typingGoesToLine, isFalse);
  });
}
