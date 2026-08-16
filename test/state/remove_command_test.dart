import 'dart:io';

import 'package:flex_commander/model/async/operation_request.dart';
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
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_remove_cmd');
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

  Future<void> press(String keys) async {
    commands().dispatch(KeyCombination.parse(keys));
    // Команда асинхронная: спрашивает, удаляет, перечитывает панель.
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> namesOf() => app.left.nodes.map((n) => n.name).toList();

  test('F8 спрашивает подтверждение и удаляет объект под курсором', () async {
    app.left.setCursorToName('notes.txt');

    await press('F8');

    expect(dialogs.confirmations, ['Delete']);
    expect(namesOf(), isNot(contains('notes.txt')));
  });

  test('отказ ничего не удаляет', () async {
    app.left.setCursorToName('notes.txt');
    dialogs.confirmed = false;

    await press('F8');

    expect(namesOf(), contains('notes.txt'));
  });

  test('удаляются все помеченные объекты, а не только под курсором', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark(); // помечает report.xlsx и уходит дальше

    await press('F8');

    expect(namesOf(), isNot(contains('notes.txt')));
    expect(namesOf(), isNot(contains('report.xlsx')));
    expect(namesOf(), contains('docs'));
  });

  test('после удаления пометка снята', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();

    await press('F8');

    expect(app.left.selection.isEmpty, isTrue);
  });

  test('на «..» команда недоступна', () async {
    app.left.setCursorToFirst();

    expect(commands().isExecutable(commands().find('file.remove')!), isFalse);
  });

  test('Shift-F8 предупреждает, что удаление безвозвратное', () async {
    app.left.setCursorToName('notes.txt');

    await press('Shift-F8');

    expect(dialogs.confirmations, ['Delete permanently']);
    expect(namesOf(), isNot(contains('notes.txt')));
  });

  test('ошибка удаления спрашивает, что делать дальше', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();
    // Объект исчез уже после того, как панель его показала.
    provider.removeEntry('/home/notes.txt');
    dialogs.choice = OperationOption.skip;

    await press('F8');

    expect(dialogs.choices.single, contains('Not found'));
    // Второй объект всё равно удалён.
    expect(namesOf(), isNot(contains('report.xlsx')));
  });

  test('обе команды видны в списке команд', () {
    expect(commands().find('file.remove')?.label, 'Delete');
    expect(commands().find('file.removePermanently')?.label, 'Delete permanently');
    expect(commands().commandFor(KeyCombination.parse('F8'))?.id, 'file.remove');
    expect(commands().commandFor(KeyCombination.parse('Shift-F8'))?.id, 'file.removePermanently');
  });
}
