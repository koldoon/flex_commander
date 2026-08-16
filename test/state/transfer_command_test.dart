import 'dart:io';

import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/app_command.dart';
import 'package:flex_commander/state/commands/command_registry.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/commands/transfer_commands.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Копирование и перенос работают без интерфейса: задать параметр и выполнить.
/// Окно — надстройка, и его в этих тестах нет.
void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/readme.md', size: 5),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
      FakeEntry.directory('/backup'),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_transfer_cmd');

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/backup'));
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

  TransferCommandBase transfer({bool move = false}) =>
      commands().create(move ? 'file.move' : 'file.copy')! as TransferCommandBase;

  List<String> namesOf(PanelController panel) => panel.nodes.map((node) => node.name).toList();

  test('по умолчанию копирует в каталог пассивной панели', () async {
    app.left.setCursorToName('notes.txt');
    final command = transfer();

    expect(command.param<String>(TransferCommandBase.destinationParam), '/backup');
    await command.execute();

    expect(namesOf(app.right), contains('notes.txt'));
    expect(namesOf(app.left), contains('notes.txt'));
  });

  test('перенос убирает объект из источника', () async {
    app.left.setCursorToName('notes.txt');

    await transfer(move: true).execute();

    expect(namesOf(app.left), isNot(contains('notes.txt')));
    expect(namesOf(app.right), contains('notes.txt'));
  });

  test('работает со всеми помеченными объектами', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();

    await transfer().execute();

    expect(namesOf(app.right), containsAll(['notes.txt', 'report.xlsx']));
    expect(namesOf(app.right), isNot(contains('docs')));
  });

  test('каталог копируется вместе с содержимым', () async {
    app.left.setCursorToName('docs');

    await transfer().execute();

    final copied = await provider.resolvePath('/backup/docs/readme.md').result;
    expect(copied, isNotNull);
  });

  test('приёмник задаётся параметром, а не панелью', () async {
    app.left.setCursorToName('notes.txt');
    final command = transfer();
    command.setParam(TransferCommandBase.destinationParam, '/home/docs');

    await command.execute();

    expect(await provider.resolvePath('/home/docs/notes.txt').result, isNotNull);
    expect(namesOf(app.right), isNot(contains('notes.txt')));
  });

  test('несуществующий приёмник — ошибка', () async {
    app.left.setCursorToName('notes.txt');
    final command = transfer();
    command.setParam(TransferCommandBase.destinationParam, '/nowhere');

    await expectLater(command.execute(), throwsA(isA<FsError>()));
  });

  test('приёмник-файл — ошибка', () async {
    app.left.setCursorToName('notes.txt');
    final command = transfer();
    command.setParam(TransferCommandBase.destinationParam, '/home/report.xlsx');

    await expectLater(
      command.execute(),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.notADirectory)),
    );
  });

  test('пустой приёмник — ошибка, а окно её показывает', () async {
    app.left.setCursorToName('notes.txt');
    final command = transfer();
    command.setParam(TransferCommandBase.destinationParam, '   ');

    // submit — то, что вызывает ядро по Enter: ошибка остаётся в окне.
    await command.submit();

    expect(command.error, isNotNull);
  });

  test('без окна вопрос о совпадении имён решается сам собой', () async {
    provider.add(FakeEntry.file('/backup/notes.txt', size: 1));
    await app.right.reload();
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();

    // Спросить некого: существующий файл пропускается, работа продолжается.
    await transfer().execute();

    expect(namesOf(app.right), containsAll(['notes.txt', 'report.xlsx']));
  });

  test('после работы пометка снята, обе панели перечитаны', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();

    await transfer(move: true).execute();

    expect(app.left.selection.isEmpty, isTrue);
    expect(namesOf(app.left), isNot(contains('notes.txt')));
    expect(namesOf(app.right), contains('notes.txt'));
  });

  test('команда сообщает о ходе работы', () async {
    app.left.setCursorToName('notes.txt');
    final command = transfer();

    final done = command.execute();
    await done;

    expect(command.isRunning, isFalse);
    expect(command.progressMessage, isNotEmpty);
    expect(command, isA<AsyncCommand>());
  });

  test('на «..» команда недоступна', () {
    app.left.setCursorToFirst();

    expect(commands().isExecutable(commands().find('file.copy')!), isFalse);
    expect(commands().isExecutable(commands().find('file.move')!), isFalse);
  });

  test('обе команды видны в списке команд и закреплены за клавишами', () {
    expect(commands().find('file.copy')?.label, 'Copy');
    expect(commands().find('file.move')?.label, 'Move');
    expect(commands().bindingsOf('file.copy').map((b) => b.keys.toString()), contains('F5'));
    expect(commands().bindingsOf('file.move').map((b) => b.keys.toString()), contains('F6'));
  });
}
