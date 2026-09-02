import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/ui/panel_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

/// Зеркало: панель на экране — это последнее, о чём рассказало ядро.
void main() {
  late InMemoryTreeProvider provider;
  late CoreServer core;
  late Link link;
  late PanelMirror panel;

  PanelSession sessionFor(String path) => PanelSession(
    settings: PanelSettings.defaults(path),
    registry: ProviderRegistry(root: provider),
    editor: const TreeTransferEngine(),
  );

  Future<void> start() async {
    core = CoreServer(left: sessionFor('/home'), right: sessionFor('/home'));
    link = LoopbackLink(core);
    final ready = await link.call(const Handshake()) as CoreReady;
    panel = PanelMirror(
      id: PanelId.left,
      link: link,
      state: ready.states[PanelId.left]!,
      listing: ready.listings[PanelId.left]!,
    );
    await panel.openPath('/home');
  }

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/deep.txt', size: 40),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.txt', size: 20),
    ])..home = '/home';
    await start();
  });

  tearDown(() async {
    panel.dispose();
    await link.dispose();
    await core.dispose();
  });

  test('зеркало показывает то, что открыло ядро', () {
    expect(panel.path, '/home');
    expect(panel.entries.map((entry) => entry.name), containsAll(['docs', 'notes.txt']));
    expect(panel.source.canWrite, isTrue);
  });

  test('дождавшись «открылось», зеркало уже знает список', () async {
    await panel.openPath('/home/docs');

    // Ни одного лишнего ожидания: событие со списком опережает ответ, и это
    // свойство языка, а не удача расписания.
    expect(panel.path, '/home/docs');
    expect(panel.entries.map((entry) => entry.name), contains('deep.txt'));
  });

  test('курсор двигается в том же кадре, а не через оборот границы', () {
    final notes = panel.entries.indexWhere((entry) => entry.name == 'notes.txt');

    panel.setCursorIndex(notes);

    // Ответа ещё нет — а курсор уже там: кадр рисует эта сторона.
    expect(panel.cursorIndex, notes);
    expect(panel.currentEntry?.name, 'notes.txt');
  });

  test('опоздавшее подтверждение курсор назад не тянет', () async {
    final last = panel.entries.length - 1;

    // Три нажатия подряд: подтверждения на первые два придут, когда курсор уже
    // ушёл дальше, и слушать их нельзя.
    panel.setCursorIndex(1);
    panel.setCursorIndex(2);
    panel.setCursorIndex(last);
    await pumpEventQueue();

    expect(panel.cursorIndex, last);
  });

  test('пометка ставится сразу и подтверждается ядром', () async {
    panel.setMarks({'notes.txt', 'report.txt'});
    expect(panel.marked, {'notes.txt', 'report.txt'});

    await pumpEventQueue();

    expect(panel.marked, {'notes.txt', 'report.txt'});
    expect(panel.markedSize, 30, reason: 'сумму считает ядро');
  });

  test('цели — помеченное, а без пометки объект под курсором', () async {
    panel.setCursorToName('notes.txt');
    await pumpEventQueue();
    expect(panel.targets.map((entry) => entry.name), ['notes.txt']);

    panel.setMarks({'report.txt'});
    await pumpEventQueue();

    expect(panel.targets.map((entry) => entry.name), ['report.txt']);
  });

  test('«..» целью не бывает', () async {
    panel.setCursorIndex(0);
    await pumpEventQueue();

    expect(panel.currentEntry?.isParent, isTrue);
    expect(panel.targets, isEmpty);
  });

  test('вход в каталог и обратно', () async {
    final docs = panel.entries.firstWhere((entry) => entry.name == 'docs');

    final blocked = await panel.enter(docs);
    expect(blocked, isNull);
    expect(panel.path, '/home/docs');

    await panel.goUp();
    expect(panel.path, '/home');
    expect(panel.currentEntry?.name, 'docs', reason: 'курсор встаёт на то, через что вошли');
  });

  test('в файл войти нельзя — он возвращается тому, кто просил', () async {
    final notes = panel.entries.firstWhere((entry) => entry.name == 'notes.txt');

    final blocked = await panel.enter(notes);

    expect(blocked?.name, 'notes.txt');
    expect(panel.path, '/home');
  });

  test('строка состояния появляется в том же кадре', () {
    panel.setStatusText('Looking for something…');

    expect(panel.statusText, 'Looking for something…');
  });

  test('посчитанный размер обновляет строку, не меняя списка', () async {
    final before = panel.entries;

    panel.measureDirectories();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pumpEventQueue();

    final docs = panel.entries.firstWhere((entry) => entry.name == 'docs');
    expect(docs.size, 40);
    expect(panel.entries.length, before.length);
  });

  test('сортировка меняет порядок', () async {
    final names = panel.entries.map((entry) => entry.name).toList();

    await panel.sortBy(FsColumn.name);

    expect(panel.entries.map((entry) => entry.name), isNot(names));
  });

  test('чужая панель зеркалу безразлична', () async {
    await link.call(const OpenPath(PanelId.right, '/home/docs'));
    await pumpEventQueue();

    expect(panel.path, '/home', reason: 'левая осталась где была');
  });
}
