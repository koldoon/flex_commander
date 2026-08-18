import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/commands/file_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Удаление тоже должно работать без интерфейса: подтверждение — дело окна,
/// а execute просто удаляет.
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
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_remove_cmd');

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = AppController(
      left: testPanel(provider: provider, settings: settings.left),
      right: testPanel(provider: provider, settings: settings.right),
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

  RemoveCommandBase remove({bool permanently = false}) =>
      commands().create(permanently ? 'file.removePermanently' : 'file.remove')! as RemoveCommandBase;

  List<String> namesOf() => app.left.nodes.map((node) => node.name).toList();

  test('удаляет объект под курсором', () async {
    app.left.setCursorToName('notes.txt');

    await remove().execute();

    expect(namesOf(), isNot(contains('notes.txt')));
  });

  test('удаляет все помеченные объекты', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();

    await remove().execute();

    expect(namesOf(), isNot(contains('notes.txt')));
    expect(namesOf(), isNot(contains('report.xlsx')));
    expect(namesOf(), contains('docs'));
  });

  test('после удаления пометка снята', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();

    await remove().execute();

    expect(app.left.selection.isEmpty, isTrue);
  });

  test('на «..» команда недоступна', () {
    app.left.setCursorToFirst();

    expect(commands().isExecutable(commands().find('file.remove')!), isFalse);
  });

  test('без окна вопрос по ошибке решается сам собой', () async {
    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    app.left.toggleCurrentMark();
    // Объект исчез уже после того, как панель его показала.
    provider.removeEntry('/home/notes.txt');

    // Спросить некого — операция берёт ответ по умолчанию и идёт дальше.
    await remove().execute();

    expect(namesOf(), isNot(contains('report.xlsx')));
  });

  test('команда сообщает о ходе работы', () async {
    app.left.setCursorToName('notes.txt');
    final command = remove();

    final done = command.execute();
    expect(command.isRunning, isTrue);
    await done;

    expect(command.isRunning, isFalse);
    expect(command.progressMessage, isNotEmpty);
    expect(command, isA<AsyncCommand>());
  });

  test('пока команда исполняется, подтверждение и отмена не срабатывают', () async {
    app.left.setCursorToName('notes.txt');
    final command = remove();

    final running = command.execute();
    expect(command.isRunning, isTrue);

    // Ядро зовёт эти методы по Enter и Esc — во время работы они молчат.
    await command.submit();
    command.dismiss();

    await running;
    expect(namesOf(), isNot(contains('notes.txt')));
  });

  test('обе команды видны в списке команд', () {
    expect(commands().find('file.remove')?.label, 'Delete');
    expect(commands().find('file.removePermanently')?.label, 'Delete permanently');
    expect(commands().bindingsOf('file.remove').map((b) => b.keys.toString()), contains('F8'));
    expect(commands().bindingsOf('file.removePermanently').map((b) => b.keys.toString()), contains('Shift-F8'));
  });
}
