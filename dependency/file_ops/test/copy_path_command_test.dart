import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Адрес объекта строкой в буфере (`docs/spec/file-clipboard.md`, §7).
void main() {
  late InMemoryTreeProvider provider;
  late FakeClipboard clipboard;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/plan.md', size: 30),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.md', size: 20),
    ]);

    clipboard = FakeClipboard();
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app =
        (await testApp(
          provider: provider,
          modules: [const Navigation(), const FileOps()],
          settings: settings,
          clipboard: clipboard,
        )).app;
    await app.start();
  });

  Future<void> copyPath() async {
    expect(app.commands.run(CopyPathCommand.commandId), isTrue, reason: 'команда не выполнилась');
    await pumpEventQueue();
  }

  test('кладёт адрес объекта под курсором', () async {
    app.left.setCursorToName('notes.txt');

    await copyPath();

    expect(clipboard.text, '/home/notes.txt');
  });

  test('помеченное — по адресу на строку', () async {
    app.left.setMarks({'/home/notes.txt', '/home/report.md'});

    await copyPath();

    // По строке на объект: так их и вставляют — в терминал, в письмо.
    expect(clipboard.text!.split('\n'), containsAll(<String>['/home/notes.txt', '/home/report.md']));
    expect(clipboard.text!.split('\n'), hasLength(2));
  });

  test('каталог годится так же, как файл', () async {
    app.left.setCursorToName('docs');

    await copyPath();

    expect(clipboard.text, '/home/docs');
  });

  test('«..» адреса не имеет — команда невыполнима', () async {
    app.left.setCursorToFirst();
    expect(app.left.currentEntry!.isParent, isTrue, reason: 'стенд ни о чём: курсор не на «..»');

    final command = app.commands.create(CopyPathCommand.commandId)!;
    expect(app.commands.isExecutable(command, const CommandInvocation()), isFalse);
  });

  test('помеченное в другом каталоге тоже попадает', () async {
    // Пометка живёт путями и бывает не только в показанном каталоге: в дереве
    // её ставят по соседним ветвям (`docs/spec/operation-targets.md`, §4).
    // Строки такой цели в списке нет вовсе — адрес спрашивается у ядра.
    app.left.setMarks({'/home/notes.txt', '/home/docs/plan.md'});
    await pumpEventQueue();

    await copyPath();

    expect(clipboard.text!.split('\n'), containsAll(<String>['/home/notes.txt', '/home/docs/plan.md']));
  });

  test('команда закреплена за Alt-Cmd-C и видна в списке команд', () {
    expect(app.commands.commandFor(KeyCombination.parse('Alt-Cmd-C'))?.id, CopyPathCommand.commandId);
  });

  group('адрес складывается из показанного каталога и имени', () {
    FileEntry entry(String directory, String name) =>
        FileEntry(name: name, kind: EntryKind.file, path: 'не важно', directoryPath: directory);

    test('у местного файла это обычный путь', () {
      expect(addressOf(entry('/Users/koldoon/dev', 'notes.txt')), '/Users/koldoon/dev/notes.txt');
    });

    test('в корне лишней косой черты не появляется', () {
      expect(addressOf(entry('/', 'usr')), '/usr');
    });

    test('у сервера адрес остаётся со схемой', () {
      // Его и вставляют — в `ssh`, в описание задачи: без схемы это не адрес.
      expect(addressOf(entry('ssh://koldoon@shark/etc', 'passwd')), 'ssh://koldoon@shark/etc/passwd');
    });

    test('внутри архива архив стоит обычным звеном', () {
      // Машинный адрес несёт схемы (`/home/a.zip:zip:/inner`), и вставить его
      // некуда (`docs/spec/file-clipboard.md`, §7).
      expect(addressOf(entry('/home/a.zip/inner', 'readme.md')), '/home/a.zip/inner/readme.md');
    });
  });
}
