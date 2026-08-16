import 'dart:io';

import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/command_registry.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/commands/navigation_commands.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Переход к имени: символ — обычный параметр команды, поэтому проверять её
/// можно без клавиатуры.
void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/home/downloads'),
      FakeEntry.file('/home/data.csv', size: 10),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/Report.pdf', size: 20),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_goto');

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

  Future<void> goTo(String character) async {
    final command = commands().create('panel.goToName')!;
    command.setParam(GoToNameCommand.characterParam, character);
    await command.execute();
  }

  String? cursorName() => app.left.currentNode?.name;

  test('курсор встаёт на первое имя с этой буквы', () async {
    await goTo('n');

    expect(cursorName(), 'notes.txt');
  });

  test('регистр не важен', () async {
    await goTo('r');

    expect(cursorName(), 'Report.pdf');
  });

  test('повторное нажатие переходит к следующему такому имени', () async {
    await goTo('d');
    expect(cursorName(), 'docs');

    await goTo('d');
    expect(cursorName(), 'downloads');

    await goTo('d');
    expect(cursorName(), 'data.csv');

    // По кругу: после последнего снова первое.
    await goTo('d');
    expect(cursorName(), 'docs');
  });

  test('если такого имени нет, курсор остаётся на месте', () async {
    app.left.setCursorToName('notes.txt');

    await goTo('z');

    expect(cursorName(), 'notes.txt');
  });

  test('«..» именем не считается', () async {
    app.left.setCursorToName('notes.txt');

    await goTo('.');

    expect(cursorName(), 'notes.txt');
  });

  test('работает в активной панели, а не всегда в левой', () async {
    app.toggleActivePanel();

    await goTo('n');

    expect(app.right.currentNode?.name, 'notes.txt');
    expect(app.left.cursorIndex, 0);
  });

  test('без символа команда ничего не делает', () async {
    app.left.setCursorToName('notes.txt');

    await commands().create('panel.goToName')!.execute();

    expect(cursorName(), 'notes.txt');
  });

  test('команда видна в списке команд', () {
    expect(commands().find('panel.goToName')?.label, 'Go to name');
  });
}
