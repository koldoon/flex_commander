import 'dart:io';

import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/command_registry.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/commands/key_combination.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Переходы по дереву: команды, которым не нужен ни диалог, ни клавиатура.
void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
      FakeEntry.directory('/usr'),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_navigation');

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      commands: defaultCommandRegistry(),
      saveDelay: const Duration(milliseconds: 5),
    );
    await app.start();
  });

  tearDown(() async {
    app.dispose();
    await temp.delete(recursive: true);
  });

  CommandRegistry commands() => app.commands;

  Future<void> run(String id) => commands().create(id)!.execute();

  group('переход в корень', () {
    test('панель открывает корневой каталог провайдера', () async {
      expect(app.left.directory?.name, 'home');

      await run('panel.root');

      expect(app.left.directory, provider.rootDirectory);
      expect(app.left.nodes.map((node) => node.name), containsAll(['home', 'usr']));
    });

    test('пометка снимается: она относилась к прежнему каталогу', () async {
      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();
      expect(app.left.selection.isEmpty, isFalse);

      await run('panel.root');

      expect(app.left.selection.isEmpty, isTrue);
    });

    test('курсор встаёт в начало списка', () async {
      app.left.setCursorToName('report.xlsx');

      await run('panel.root');

      expect(app.left.cursorIndex, 0);
    });

    test('работает в активной панели', () async {
      app.toggleActivePanel();

      await run('panel.root');

      expect(app.right.directory, provider.rootDirectory);
      expect(app.left.directory?.name, 'home');
    });

    test('в самом корне команда недоступна', () async {
      await run('panel.root');

      // Идти больше некуда — кнопка и клавиша ничего не делают.
      expect(commands().isExecutable(commands().find('panel.root')!), isFalse);
    });

    test('команда видна в списке команд и закреплена за клавишей', () {
      expect(commands().find('panel.root')?.label, 'Root');
      // Вне macOS «командная» клавиша — Ctrl, поэтому сравнение идёт с тем же
      // разбором, каким привязка и создавалась.
      expect(
        commands().bindingsOf('panel.root').map((binding) => binding.keys),
        contains(KeyCombination.parse('Cmd-/')),
      );
    });
  });
}
