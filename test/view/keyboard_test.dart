import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/view/function_bar/function_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;
  late List<String> opened;

  // Платформа в widget-тестах не macOS, поэтому «командная» клавиша здесь —
  // Ctrl: ровно то, во что KeyCombination сворачивает Cmd вне macOS.
  const commandKey = LogicalKeyboardKey.control;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
      FakeEntry.file('/home/.hidden', size: 1),
      FakeEntry.file('/home/docs/readme.md', size: 30),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_keyboard');
    opened = [];

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home/docs'));
    // Команды подменяются, а привязки остаются штатными: они ссылаются на
    // команды по идентификатору, поэтому подмена реализации их не касается.
    // Открытие системой подменяется записью в список: команды создаются
    // фабриками, поэтому подставить свою реализацию — это подставить фабрику.
    final commands = CommandRegistry(defaultCommands(opener: (path) async => opened.add(path)), defaultKeyBindings());
    app = AppController(
      left: testPanel(provider: provider, settings: settings.left),
      right: testPanel(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      commands: commands,
      saveDelay: const Duration(milliseconds: 5),
    );
  });

  tearDown(() async {
    app.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> modifiers = const [],
  }) async {
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pumpAndSettle();
    // Даём сработать отложенной записи настроек, если команда её запланировала.
    await tester.pump(const Duration(milliseconds: 20));
  }

  group('курсор', () {
    testWidgets('стрелки двигают курсор', (tester) async {
      await pumpApp(tester);
      expect(app.left.cursorIndex, 0);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(app.left.cursorIndex, 1);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(app.left.cursorIndex, 0);
    });

    testWidgets('удержание стрелки повторяет нажатие', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(app.left.cursorIndex, 3);
    });

    testWidgets('Home и End прыгают к краям списка', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.end);
      expect(app.left.cursorIndex, app.left.nodes.length - 1);

      await press(tester, LogicalKeyboardKey.home);
      expect(app.left.cursorIndex, 0);
    });

    testWidgets('стрелки влево и вправо тоже прыгают к краям', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(app.left.cursorIndex, app.left.nodes.length - 1);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(app.left.cursorIndex, 0);
    });

    testWidgets('PgDn сдвигает на страницу по числу видимых строк', (tester) async {
      await pumpApp(tester);
      // В каталоге меньше строк, чем помещается на экране: курсор упирается в конец.
      await press(tester, LogicalKeyboardKey.pageDown);

      expect(app.left.pageSize, greaterThan(1));
      expect(app.left.cursorIndex, app.left.nodes.length - 1);
    });
  });

  group('переход к имени', () {
    testWidgets('буква ставит курсор на имя, которое с неё начинается', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.keyN);

      expect(app.left.currentNode?.name, 'notes.txt');
    });

    testWidgets('разные буквы ведут к разным именам', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.keyD);
      expect(app.left.currentNode?.name, 'docs');

      await press(tester, LogicalKeyboardKey.keyR);
      expect(app.left.currentNode?.name, 'report.xlsx');
    });

    testWidgets('пробел по-прежнему помечает, а не ищет', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.space);

      expect(app.left.selection.names, contains('notes.txt'));
    });
  });

  group('панели', () {
    testWidgets('Tab переключает панель и не уводит фокус на кнопки', (tester) async {
      await pumpApp(tester);
      expect(app.activePanel, app.left);

      await press(tester, LogicalKeyboardKey.tab);
      expect(app.activePanel, app.right);

      await press(tester, LogicalKeyboardKey.tab);
      expect(app.activePanel, app.left);

      // Фокус остался у обработчика клавиатуры: кнопки его не перехватили.
      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.context?.widget, isNot(isA<FunctionButton>()));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(app.left.cursorIndex, 1);
    });
  });

  group('навигация по дереву', () {
    testWidgets('Enter входит в каталог', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('bin');

      await press(tester, LogicalKeyboardKey.enter);

      expect(app.left.directory?.pathString, '/home/bin');
      expect(opened, isEmpty);
    });

    testWidgets('Enter на файле отдаёт его системе', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');

      await press(tester, LogicalKeyboardKey.enter);

      expect(opened, ['/home/notes.txt']);
      expect(app.left.directory?.pathString, '/home');
    });

    testWidgets('файл из источника без настоящих путей системе не отдаётся', (tester) async {
      // Так выглядит файл внутри архива или на сервере: пути, который поймёт
      // внешняя программа, у него нет, и открывать его будет свой просмотрщик.
      provider.capabilities = readOnlyCapabilities;
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');

      await press(tester, LogicalKeyboardKey.enter);

      expect(opened, isEmpty);
      // Панель осталась на месте: войти в файл всё равно нельзя.
      expect(app.left.directory?.pathString, '/home');
    });

    testWidgets('Cmd-/ уводит в корень из любого каталога', (tester) async {
      await pumpApp(tester);
      expect(app.left.directory?.pathString, '/home');

      await press(tester, LogicalKeyboardKey.slash, modifiers: [commandKey]);

      expect(app.left.directory, provider.rootDirectory);
    });

    testWidgets('Backspace поднимает наверх и ставит курсор на покинутый каталог', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('docs');
      await press(tester, LogicalKeyboardKey.enter);
      expect(app.left.directory?.pathString, '/home/docs');

      await press(tester, LogicalKeyboardKey.backspace);

      expect(app.left.directory?.pathString, '/home');
      expect(app.left.currentNode?.name, 'docs');
    });

    testWidgets('Enter на ".." эквивалентен Backspace', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('docs');
      await press(tester, LogicalKeyboardKey.enter);

      app.left.setCursorToFirst();
      await press(tester, LogicalKeyboardKey.enter);

      expect(app.left.directory?.pathString, '/home');
    });

    testWidgets('Cmd-Shift-H показывает скрытые объекты', (tester) async {
      await pumpApp(tester);
      expect(app.left.nodes.map((node) => node.name), isNot(contains('.hidden')));

      await press(tester, LogicalKeyboardKey.keyH, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);

      expect(app.left.showHidden, isTrue);
      expect(app.left.nodes.map((node) => node.name), contains('.hidden'));

      await press(tester, LogicalKeyboardKey.keyH, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);

      expect(app.left.showHidden, isFalse);
      expect(app.left.nodes.map((node) => node.name), isNot(contains('.hidden')));
    });
  });

  group('пометка', () {
    testWidgets('Space помечает объект и сдвигает курсор', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');

      await press(tester, LogicalKeyboardKey.space);

      expect(app.left.selection.names, {'notes.txt'});
      expect(app.left.currentNode?.name, 'report.xlsx');
    });

    testWidgets('Space на ".." ничего не помечает', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToFirst();

      await press(tester, LogicalKeyboardKey.space);

      expect(app.left.selection.isEmpty, isTrue);
    });

    testWidgets('Esc снимает пометку', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await press(tester, LogicalKeyboardKey.space);

      await press(tester, LogicalKeyboardKey.escape);

      expect(app.left.selection.isEmpty, isTrue);
    });

    testWidgets('Cmd-A помечает всё, кроме ".."', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.keyA, modifiers: const [commandKey]);

      expect(app.left.selection.length, app.left.nodes.length - 1);
      expect(app.left.selection.names, isNot(contains('..')));

      // Пометка каталогов запускает фоновый подсчёт их размера — даём ему
      // отработать, иначе тест закончится с недоделанной работой.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    });
  });

  group('нижняя панель', () {
    testWidgets('подписи берутся из реестра команд', (tester) async {
      await pumpApp(tester);

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      final f5 = tester.widget<FunctionButton>(
        find.ancestor(of: find.text('Copy'), matching: find.byType(FunctionButton)),
      );
      expect(f5.number, 5);
      // Файловые операции ещё не реализованы: кнопка показана, но неактивна.
      expect(f5.enabled, isFalse);
    });

    testWidgets('команда, поставленная после запуска, появляется на кнопке', (tester) async {
      await pumpApp(tester);
      expect(find.text('Later'), findsNothing);

      // Так команду ставит модуль: приложение уже собрано и нарисовано.
      app.commands.install(() => PlaceholderCommand(id: 'test.later', label: 'Later'));
      app.commands.bind(KeyBinding('F9', 'test.later'));
      await tester.pump();

      final f9 = tester.widget<FunctionButton>(
        find.ancestor(of: find.text('Later'), matching: find.byType(FunctionButton)),
      );
      expect(f9.number, 9);
    });
  });
}
