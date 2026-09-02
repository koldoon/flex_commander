import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Переименование: имя меняется, содержимое — нет.
void main() {
  late InMemoryTreeProvider provider;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.md', size: 20),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: [const Navigation(), const FileOps()], settings: settings)).app;
    await app.start();
  });

  RenameCommand rename() => app.commands.create('file.rename')! as RenameCommand;

  List<String> namesOf() => app.left.entries.map((node) => node.name).toList();

  Future<void> renameCursorTo(String name) async {
    await rename().executeWith({RenameCommand.nameParam: name});
  }

  test('меняет имя объекта под курсором', () async {
    app.left.setCursorToName('notes.txt');

    await renameCursorTo('заметки.txt');

    expect(namesOf(), contains('заметки.txt'));
    expect(namesOf(), isNot(contains('notes.txt')));
  });

  test('курсор остаётся на объекте — по новому имени', () async {
    // Иначе он прыгает в начало ровно тогда, когда человек смотрит на
    // результат.
    app.left.setCursorToName('notes.txt');

    await renameCursorTo('заметки.txt');

    expect(app.left.currentEntry?.name, 'заметки.txt');
  });

  test('пробелы по краям имени и по краям основы срезаются', () async {
    app.left.setCursorToName('notes.txt');

    await renameCursorTo('  отчёт  .txt  ');

    expect(namesOf(), contains('отчёт.txt'));
  });

  test('занятое имя отказывает, а не затирает чужой файл', () async {
    app.left.setCursorToName('notes.txt');

    await expectLater(
      renameCursorTo('report.md'),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.alreadyExists)),
    );

    // Оба на месте: чужой файл не тронут.
    expect(namesOf(), containsAll(<String>['notes.txt', 'report.md']));
  });

  test('пустое имя не годится', () async {
    app.left.setCursorToName('notes.txt');

    await expectLater(
      renameCursorTo('   '),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.invalidName)),
    );
  });

  test('то же имя ничего не меняет и не жалуется', () async {
    app.left.setCursorToName('notes.txt');

    await renameCursorTo('notes.txt');

    expect(namesOf(), contains('notes.txt'));
  });

  test('каталог переименовывается так же', () async {
    app.left.setCursorToName('docs');

    await renameCursorTo('документы');

    expect(namesOf(), contains('документы'));
  });

  test('вторая панель, стоящая здесь же, тоже видит новое имя', () async {
    // Найдено на живом: обе панели смотрят в один каталог, а перечитывалась
    // только та, в которой работали.
    expect(app.right.path, '/home', reason: 'обе панели в одном каталоге');
    app.left.setCursorToName('notes.txt');

    await renameCursorTo('заметки.txt');

    expect(app.right.entries.map((node) => node.name), contains('заметки.txt'));
    expect(app.right.entries.map((node) => node.name), isNot(contains('notes.txt')));
  });

  test('панель в другом каталоге не перечитывается зря', () async {
    await app.right.openPath('/home/docs');
    app.left.setCursorToName('notes.txt');

    await renameCursorTo('заметки.txt');

    expect(app.right.path, '/home/docs');
  });

  group('когда команда невыполнима', () {
    test('на «..»', () async {
      app.left.setCursorToName('..');

      expect(rename().isExecutable(CommandContext.of(app)), isFalse);
    });

    test('там, где провайдер не умеет переименовывать', () async {
      // Архив: переименование означало бы пересборку целиком, а о ней
      // полагается спрашивать заранее (`spec/rename.md`, §4).
      provider.capabilities = const ProviderCapabilities(maxConcurrency: 1);
      app.left.setCursorToName('notes.txt');

      expect(rename().isExecutable(CommandContext.of(app)), isFalse);
    });
  });
}
