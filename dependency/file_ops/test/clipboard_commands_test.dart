import 'package:fc_api/fc_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Файловый буфер обмена (`docs/spec/file-clipboard.md`).
///
/// Здесь — то, что кладут и чем это оборачивается; сама вставка открывает окно
/// работы, и проверяется она целиком в `clipboard_paste_view_test.dart`.
void main() {
  late InMemoryTreeProvider provider;
  late FakeFileClipboard files;
  late AppController app;

  Future<AppController> build({FakeFileClipboard? clipboard}) async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/target'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.md', size: 20),
    ]);
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home/target'));
    final runtime = await testApp(
      provider: provider,
      modules: [const Navigation(), const FileOps()],
      settings: settings,
      fileClipboard: clipboard,
    );
    await runtime.app.start();
    return runtime.app;
  }

  setUp(() async {
    files = FakeFileClipboard();
    app = await build(clipboard: files);
  });

  Future<void> run(String commandId) async {
    expect(app.commands.run(commandId), isTrue, reason: 'команда $commandId не выполнилась');
    // Вставка запускает работу и её не ждёт — как всякая команда: нажатие не
    // может стоять и ждать конца копирования. Прогон ждёт за него.
    await pumpEventQueue(times: 200);
  }

  List<String> namesIn(Session panel) => panel.entries.map((entry) => entry.name).toList();

  test('копирование кладёт помеченное адресами', () async {
    app.left.setMarks({'/home/notes.txt', '/home/report.md'});
    await pumpEventQueue();

    await run(ClipboardCopyCommand.commandId);

    expect(files.files!.addresses, containsAll(<String>['/home/notes.txt', '/home/report.md']));
    expect(files.files!.move, isFalse);
    expect(files.files!.ours, isTrue);
  });

  test('без пометки берётся объект под курсором', () async {
    app.left.setCursorToName('notes.txt');

    await run(ClipboardCopyCommand.commandId);

    expect(files.files!.addresses, ['/home/notes.txt']);
  });

  test('вырезание ничего не трогает, пока не вставили', () async {
    app.left.setCursorToName('notes.txt');

    await run(ClipboardCutCommand.commandId);

    expect(files.files!.move, isTrue);
    expect(namesIn(app.left), contains('notes.txt'), reason: '«вырезать» — намерение, а не действие');
  });

  test('пустой буфер говорит о себе, а не молчит', () async {
    files.clear();
    app.activate(app.right);

    expect(app.commands.run(ClipboardPasteCommand.copyId), isTrue);
    // Коротко: сообщение живёт по таймеру, и долгое ожидание его переживёт.
    await pumpEventQueue(times: 3);

    expect(app.toasts.current?.message, contains('clipboard'), reason: 'нажатие осталось без ответа');
  });

  test('без службы команд буфера нет, а адрес копируется', () async {
    app = await build();

    final copy = app.commands.create(ClipboardCopyCommand.commandId)!;
    app.left.setCursorToName('notes.txt');
    expect(app.commands.isExecutable(copy, const CommandInvocation()), isFalse);

    final address = app.commands.create(CopyPathCommand.commandId)!;
    expect(app.commands.isExecutable(address, const CommandInvocation()), isTrue);
  });

  test('клавиши закреплены за командами буфера', () {
    expect(app.commands.commandFor(KeyCombination.parse('Cmd-C'))?.id, ClipboardCopyCommand.commandId);
    expect(app.commands.commandFor(KeyCombination.parse('Cmd-X'))?.id, ClipboardCutCommand.commandId);
    expect(app.commands.commandFor(KeyCombination.parse('Cmd-V'))?.id, ClipboardPasteCommand.copyId);
    expect(app.commands.commandFor(KeyCombination.parse('Alt-Cmd-V'))?.id, ClipboardPasteCommand.moveId);
  });
}
