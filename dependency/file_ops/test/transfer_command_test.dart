import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Копирование и перенос работают без интерфейса: задать параметр и выполнить.
/// Окно — надстройка, и его в этих тестах нет.
void main() {
  late InMemoryTreeProvider provider;
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

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/backup'));
    app = (await testApp(provider: provider, modules: [const Navigation(), const FileOps()], settings: settings)).app;
    await app.start();
  });

  CommandService commands() => app.commands;

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

  group('источник только для чтения', () {
    /// Левая панель — архив, открытый на просмотр: дерево и содержимое есть,
    /// менять нечем. Правая — обычный диск.
    Future<AppController> openArchive(InMemoryReadOnlyProvider archive) async {
      // Приёмник умеет принимать байты — иначе потоку не во что литься.
      final disk = InMemoryContentProvider([FakeEntry.directory('/backup')]);
      final settings = AppSettings(left: PanelSettings.defaults('/arc'), right: PanelSettings.defaults('/backup'));
      final it =
          (await testApp(
            provider: archive,
            rightProvider: disk,
            modules: [const Navigation(), const FileOps()],
            settings: settings,
          )).app;
      await it.start();
      it.left.setCursorToName('inside.txt');
      return it;
    }

    List<FakeEntry> entries() => [
      FakeEntry.directory('/arc'),
      FakeEntry.file('/arc/inside.txt', content: [1, 2, 3]),
    ];

    test('копировать из него можно: принимает приёмник, а не источник', () async {
      final app = await openArchive(InMemoryArchiveProvider(entries()));

      expect(app.commands.isExecutable(app.commands.find('file.copy')!), isTrue);
      // Перенос убрал бы объект из архива, а убирать в нём нечем.
      expect(app.commands.isExecutable(app.commands.find('file.move')!), isFalse);
    });

    test('копирование доходит до приёмника потоком', () async {
      final app = await openArchive(InMemoryArchiveProvider(entries()));

      await (app.commands.create('file.copy')!..setParam('destination', '/backup')).execute();

      expect(app.right.nodes.map((node) => node.name), contains('inside.txt'));
    });

    test('без содержимого копировать нечем, и команда об этом не врёт', () async {
      // Дерево есть, байтов нет: взять файл неоткуда.
      final app = await openArchive(InMemoryReadOnlyProvider(entries()));

      final command = app.commands.create('file.copy')!..setParam('destination', '/backup');
      await command.execute();

      expect(app.right.nodes.map((node) => node.name), isNot(contains('inside.txt')));
    });
  });

  test('обе команды видны в списке команд и закреплены за клавишами', () {
    expect(commands().find('file.copy')?.label, 'Copy');
    expect(commands().find('file.move')?.label, 'Move');
    expect(commands().bindingsOf('file.copy').map((b) => b.keys.toString()), contains('F5'));
    expect(commands().bindingsOf('file.move').map((b) => b.keys.toString()), contains('F6'));
  });
}
