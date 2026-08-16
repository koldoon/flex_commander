import 'dart:io';

import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/command_registry.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/commands/file_commands.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Команда должна работать и без интерфейса: задать параметры и выполнить.
/// Именно так её вызовут меню, сценарий или командная строка.
void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/notes.txt', size: 10),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_mkdir_cmd');

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

  MakeDirectoryCommand makeDirectory() => commands().create('file.mkdir')! as MakeDirectoryCommand;

  List<String> namesOf() => app.left.nodes.map((node) => node.name).toList();

  test('создаёт каталог по заданному параметру', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'docs');

    await command.execute();

    expect(namesOf(), contains('docs'));
  });

  test('курсор встаёт на созданный каталог', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'docs');

    await command.execute();

    expect(app.left.currentNode?.name, 'docs');
  });

  test('лишние пробелы в имени отбрасываются', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, '  docs  ');

    await command.execute();

    expect(namesOf(), contains('docs'));
  });

  test('пустое имя — ошибка, а не молчаливый отказ', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, '   ');

    await expectLater(
      command.execute(),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.invalidName)),
    );
  });

  test('существующее имя даёт ошибку', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'bin');

    await expectLater(
      command.execute(),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
    );
  });

  test('каталог создаётся в активной панели', () async {
    app.toggleActivePanel();
    await app.right.openPath('/home/bin');

    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'tools');
    await command.execute();

    expect(app.right.nodes.map((node) => node.name), contains('tools'));
    expect(namesOf(), isNot(contains('tools')));
  });

  test('подтверждение выполняет команду и закрывает окно', () async {
    // Так это делает ядро по Enter: параметры уже заданы, остаётся выполнить.
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'docs');

    await command.submit();

    expect(namesOf(), contains('docs'));
    expect(command.error, isNull);
  });

  test('ошибка остаётся в команде, а не улетает наружу', () async {
    final command = makeDirectory()..setParam(MakeDirectoryCommand.nameParam, 'bin');

    // submit — общее поведение ядра: ошибку показывает окно, поэтому наружу
    // она не выбрасывается.
    await command.submit();

    expect(command.error, contains('Already exists'));
  });

  test('команда доступна и закреплена за клавишей', () {
    final command = commands().find('file.mkdir')!;

    expect(command.label, 'Mk Dir');
    expect(commands().isExecutable(command), isTrue);
    expect(commands().bindingsOf('file.mkdir').map((b) => b.keys.toString()), contains('F7'));
  });
}
