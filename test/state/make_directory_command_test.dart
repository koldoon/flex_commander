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

import '../fake/fake_user_interaction.dart';
import '../fake/in_memory_tree_provider.dart';

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late FakeUserInteraction dialogs;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/notes.txt', size: 10),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_mkdir_cmd');
    dialogs = FakeUserInteraction();

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      commands: defaultCommandRegistry(),
      dialogs: dialogs,
      saveDelay: const Duration(milliseconds: 5),
    );
    await app.start();
  });

  tearDown(() async {
    app.dispose();
    await temp.delete(recursive: true);
  });

  CommandRegistry commands() => app.commands;

  Future<void> pressF7() async {
    commands().dispatch(KeyCombination.parse('F7'));
    // Команда асинхронная: спрашивает имя, создаёт каталог, перечитывает панель.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('F7 спрашивает имя и создаёт каталог', () async {
    dialogs.answer = 'docs';

    await pressF7();

    expect(dialogs.prompts, ['Create directory']);
    expect(app.left.nodes.map((n) => n.name), contains('docs'));
    expect(dialogs.errors, isEmpty);
  });

  test('курсор встаёт на созданный каталог', () async {
    dialogs.answer = 'docs';

    await pressF7();

    expect(app.left.currentNode?.name, 'docs');
  });

  test('отказ пользователя ничего не создаёт', () async {
    dialogs.answer = null;

    await pressF7();

    expect(app.left.nodes.map((n) => n.name), isNot(contains('docs')));
    expect(dialogs.errors, isEmpty);
  });

  test('пустое имя ничего не создаёт', () async {
    dialogs.answer = '   ';

    await pressF7();

    // "..", bin, notes.txt — и ничего нового.
    expect(app.left.nodes.map((n) => n.name), ['..', 'bin', 'notes.txt']);
    expect(dialogs.errors, isEmpty);
  });

  test('имя существующего объекта показывает ошибку', () async {
    dialogs.answer = 'bin';

    await pressF7();

    expect(dialogs.errors.single, contains('Already exists'));
  });

  test('каталог создаётся в активной панели', () async {
    app.toggleActivePanel();
    await app.right.openPath('/home/bin');
    dialogs.answer = 'tools';

    await pressF7();

    expect(app.right.nodes.map((n) => n.name), contains('tools'));
    expect(app.left.nodes.map((n) => n.name), isNot(contains('tools')));
  });

  test('каталог создаётся и сочетанием, не занятым системой', () async {
    // На macOS F7 по умолчанию перехватывает система, поэтому у команды есть
    // и второе сочетание.
    dialogs.answer = 'docs';

    commands().dispatch(KeyCombination.parse('Shift-Cmd-N'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(app.left.nodes.map((n) => n.name), contains('docs'));
  });

  test('команда доступна и выполнима из списка команд', () {
    final command = commands().find('file.mkdir')!;

    expect(command.label, 'Mk Dir');
    expect(commands().isExecutable(command), isTrue);
    expect(commands().commandFor(KeyCombination.parse('F7')), same(command));
  });
}
