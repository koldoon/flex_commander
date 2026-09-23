import 'dart:async';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/ui/session_mirror.dart';
import 'package:flex_commander/ui/remote_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_panels/fc_panels.dart';

/// Зеркало: панель на экране — это последнее, о чём рассказало ядро.
/// Линк, придерживающий события: подтверждения ядра приходят тогда, когда их
/// отпустит проверка.
///
/// Так и живёт настоящая сборка: ядро в своём изоляте, и пока оно считает
/// размеры помеченных каталогов, подтверждения отстают от нажатий на несколько
/// штук (`docs/spec/client-server.md`, §5.5).
class _LaggingLink implements Link {
  _LaggingLink(this._link) {
    _link.events.listen(_held.add);
  }

  final Link _link;
  final List<CoreEvent> _held = [];
  final StreamController<CoreEvent> _events = StreamController<CoreEvent>.broadcast();

  /// Что придержано — проверке, которой важен **порядок** подтверждений.
  List<CoreEvent> get held => List.unmodifiable(_held);

  /// Отпустить всё придержанное — по одному, в порядке прихода.
  Future<void> releaseAll() async {
    while (_held.isNotEmpty) {
      await releaseOne();
    }
  }

  /// Отпустить одно придержанное подтверждение — самое старое.
  Future<void> releaseOne() async {
    if (_held.isNotEmpty) {
      _events.add(_held.removeAt(0));
    }
    await pumpEventQueue();
  }

  @override
  Stream<CoreEvent> get events => _events.stream;

  @override
  Future<CoreReply> call(CoreRequest request) => _link.call(request);

  @override
  void tell(CoreRequest request) => _link.tell(request);

  @override
  bool get isOpen => _link.isOpen;

  @override
  Future<void> dispose() async {
    await _events.close();
    await _link.dispose();
  }
}

void main() {
  late InMemoryTreeProvider provider;
  late CoreServer core;
  late Link link;
  late SessionMirror panel;

  PanelSession sessionFor(String path) => PanelSession(
    settings: PanelSettings.defaults(path),
    registry: ProviderRegistry(root: provider),
    editor: const TreeTransferEngine(),
    columns: testColumnSorting(),
  );

  Future<void> start() async {
    core = CoreServer(
      left: sessionFor('/home'),
      right: sessionFor('/home'),
      // Реестр нужен ссылке на строку по пути: чужую строку разбирает корень
      // дерева, а не панель. В сборке приложения он есть всегда.
      registry: ProviderRegistry(root: provider),
    );
    link = LoopbackLink(core);
    final ready = await link.call(const Handshake()) as CoreReady;
    panel = SessionMirror(
      id: PanelId.left,
      link: link,
      state: ready.states[PanelId.left]!,
      listing: ready.listings[PanelId.left]!,
      columns: testPanelColumns(),
    );
    await panel.openPath('/home');
  }

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/deep.txt', size: 40),
      // Тёзка в соседнем каталоге: по имени их не различить, по пути — да.
      FakeEntry.file('/home/docs/notes.txt', size: 50),
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
    expect(panel.currentPath, '/home');
    expect(panel.entries.map((entry) => entry.name), containsAll(['docs', 'notes.txt']));
    expect(panel.source.canWrite, isTrue);
  });

  test('дождавшись «открылось», зеркало уже знает список', () async {
    await panel.openPath('/home/docs');

    // Ни одного лишнего ожидания: событие со списком опережает ответ, и это
    // свойство языка, а не удача расписания.
    expect(panel.currentPath, '/home/docs');
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

  test('курсор ставится путём: список сменился, а строка та же', () async {
    // Так двигает курсор вид, который сам меняет список: номер, пока заявка
    // едет через границу, успевает означать другую строку
    // (`docs/spec/panel-view-columns.md`, §5).
    panel.setCursorToPath('/home/report.txt');
    expect(panel.currentEntry?.name, 'report.txt', reason: 'кадр рисует эта сторона');

    await pumpEventQueue();
    expect(panel.currentEntry?.path, '/home/report.txt', reason: 'и ядро встало туда же');
  });

  test('новый список приехал раньше подтверждения — курсор не прыгает', () async {
    // Живая находка 17 сентября 2026: строки и курсор приезжают **разными**
    // событиями. Пока своя заявка не подтверждена, зеркало держало свой
    // номер, — а если за это время приехал новый список, тот же номер означал
    // уже соседнюю строку, и курсор на кадр прыгал назад.
    final held = _LaggingLink(link);
    final mirror = SessionMirror(
      id: PanelId.left,
      link: held,
      state: panel.state,
      listing: panel.listing,
      columns: testPanelColumns(),
    );
    addTearDown(mirror.dispose);

    mirror.setCursorToPath('/home/report.txt');
    final was = mirror.currentEntry?.path;

    // В каталоге появилось пополнение — список приедет раньше, чем ответ на
    // заявку о курсоре.
    provider.add(FakeEntry.file('/home/aaa-first.txt', size: 1));
    await panel.reload();
    await pumpEventQueue();
    for (var i = 0; i < 6; i++) {
      await held.releaseOne();
    }

    expect(mirror.currentEntry?.path, was, reason: 'курсор держится за строку, а не за её номер');
  });

  test('пометка ставится сразу и подтверждается ядром', () async {
    panel.setMarks({'/home/notes.txt', '/home/report.txt'});
    expect(panel.markedPaths, {'/home/notes.txt', '/home/report.txt'});

    await pumpEventQueue();

    expect(panel.markedPaths, {'/home/notes.txt', '/home/report.txt'});
    expect(panel.markedSize, 30, reason: 'сумму считает ядро');
  });

  test('цели — помеченное, а без пометки объект под курсором', () async {
    panel.setCursorToName('notes.txt');
    await pumpEventQueue();
    expect(panel.targets.map((entry) => entry.name), ['notes.txt']);

    panel.setMarks({'/home/report.txt'});
    await pumpEventQueue();

    expect(panel.targets.map((entry) => entry.name), ['report.txt']);
  });

  test('пометка под курсором видна в том же кадре', () async {
    // Ядро могло уйти считать размеры помеченного каталога, и ответа ждать
    // долго: пометка обязана появиться тем же кадром, что и нажатие
    // (живой разбор 17 сентября 2026 — пометка догоняла курсор).
    final notes = panel.entries.indexWhere((entry) => entry.name == 'notes.txt');
    panel.setCursorIndex(notes);

    panel.toggleCurrentMark(step: false);
    expect(panel.markedPaths, {'/home/notes.txt'}, reason: 'ответа ещё нет — а пометка уже видна');

    await pumpEventQueue();
    expect(panel.markedPaths, {'/home/notes.txt'}, reason: 'и ядро согласилось');

    panel.toggleCurrentMark(step: false);
    expect(panel.markedPaths, isEmpty, reason: 'снимается так же сразу');
    await pumpEventQueue();
    expect(panel.markedPaths, isEmpty);
  });

  test('список, собравшийся сам, курсора не несёт', () async {
    // Человек пошёл по списку, а тот прирос — находками, слежением,
    // перечитыванием. Подсказки «встань в начало» в таком списке нет вовсе,
    // и строка остаётся за человеком (`docs/spec/client-server.md`, §5.6.4).
    panel.setCursorToName('report.txt');
    await pumpEventQueue();
    final was = panel.currentEntry?.path;

    provider.add(FakeEntry.file('/home/aaa-new.txt', size: 1));
    await panel.reload();
    await pumpEventQueue();

    expect(panel.listing.cursor, isEmpty, reason: 'перечитывание курсора не ставит');
    expect(panel.currentEntry?.path, was, reason: 'курсор остался на своей строке');
  });

  test('вход в каталог курсор ставит — и говорит об этом списком', () async {
    await panel.openPath('/home/docs');
    await pumpEventQueue();
    expect(panel.currentPath, '/home/docs');

    await panel.goUp();
    await pumpEventQueue();

    expect(panel.listing.cursor, '/home/docs', reason: 'подъём ставит курсор на покинутый каталог');
    expect(panel.currentEntry?.name, 'docs');
  });

  test('пробел шагает курсором в том же кадре, что и помечает', () async {
    // Пробел — одно действие: помечает и переходит к следующему. Показывать
    // сразу только половину значит отдать человеку курсор, отстающий от его
    // нажатий: пока ядро обходит помеченный каталог, ответ отстаёт
    // (живой разбор 23 сентября 2026).
    final lagging = _LaggingLink(link);
    final slow = SessionMirror(
      id: PanelId.left,
      link: lagging,
      state: panel.state,
      listing: panel.listing,
      columns: testPanelColumns(),
    );
    addTearDown(slow.dispose);

    // С каталога: строк под ним хватает на шаг и ещё один, а пометка каталога
    // — как раз тот случай, когда ядро уходит считать и отвечает нескоро.
    slow.setCursorToName('docs');
    final was = slow.cursorIndex;

    slow.toggleCurrentMark();

    expect(slow.markedPaths, {'/home/docs'}, reason: 'ответа ещё нет — а пометка видна');
    expect(slow.cursorIndex, was + 1, reason: 'и шаг тоже: это одно действие');

    // Стрелка, нажатая следом, считается от **новой** строки, а не от
    // вчерашней: иначе нажатие пропадало бы.
    slow.moveCursor(1);
    expect(slow.cursorIndex, was + 2);

    await lagging.releaseAll();
    expect(slow.cursorIndex, was + 2, reason: 'ядро согласилось, курсор назад не дёрнулся');
  });

  test('пробел не шлёт наружу свежий номер со вчерашним курсором', () async {
    // Пометка уведомляет о себе, и каждое уведомление уносит состояние за
    // границу. Сделай её раньше шага — и наружу уедет состояние со свежим
    // номером заявки и **старым** курсором; та сторона примет его за
    // подтверждение и вернёт курсор на строку назад. Живьём это и был дёрганый
    // курсор при обсчёте размеров (разбор 23 сентября 2026).
    final lagging = _LaggingLink(link);
    final slow = SessionMirror(
      id: PanelId.left,
      link: lagging,
      state: panel.state,
      listing: panel.listing,
      columns: testPanelColumns(),
    );
    addTearDown(slow.dispose);

    slow.setCursorToName('docs');
    await lagging.releaseAll();
    final was = slow.cursorIndex;

    slow.toggleCurrentMark();
    await pumpEventQueue();

    final seq = slow.state.cursorSeq;
    final stale = [
      for (final event in lagging.held)
        if (event case PanelChanged(:final state) when state.cursorSeq >= seq && state.cursorIndex == was) state,
    ];
    expect(stale, isEmpty, reason: 'со свежим номером наружу уезжает только сделанный шаг');
  });

  test('пробел на строке, которая не помечается, курсора не двигает', () async {
    await panel.openPath('/home');
    panel.setCursorIndex(0);
    expect(panel.currentEntry?.isParent, isTrue);

    panel.toggleCurrentMark();
    await pumpEventQueue();

    expect(panel.markedPaths, isEmpty);
    expect(panel.cursorIndex, 0, reason: '«..» не помечается — и шага тут нет');
  });

  test('опоздавшее подтверждение пометки не отбирает поставленное', () async {
    // Так помечают в дереве, зажав `Space`: заявки уходят пачкой, а
    // подтверждения на первые приходят, когда помечено уже больше. Слушать их
    // значит терять пометку — и на глазах у человека.
    final lagging = _LaggingLink(link);
    final slow = SessionMirror(id: PanelId.left, link: lagging, state: panel.state, listing: panel.listing);
    addTearDown(slow.dispose);

    slow.setMarks({'/home/notes.txt'});
    slow.setMarks({'/home/notes.txt', '/home/report.txt'});
    // До оборота границы видно всё, что нажали.
    expect(slow.markedPaths, hasLength(2));

    // Приходит подтверждение **первой** заявки: помечено в нём одно.
    await lagging.releaseOne();

    expect(slow.markedPaths, {'/home/notes.txt', '/home/report.txt'}, reason: 'вторая пометка никуда не делась');
  });

  test('targets — строки этого списка, allTargets — всё помеченное', () async {
    panel.setMarks({'/home/notes.txt', '/home/docs/deep.txt'});
    await pumpEventQueue();

    expect(panel.targets.map((entry) => entry.name), ['notes.txt'], reason: 'чужой строки в этом списке нет');
    expect(panel.targetPaths, {'/home/notes.txt', '/home/docs/deep.txt'}, reason: 'а путь есть у обеих');
    expect(panel.hasTargets, isTrue);

    final all = await panel.allTargets();

    expect(all.map((entry) => entry.name), containsAll(['notes.txt', 'deep.txt']));
    expect({for (final entry in all) entry.directoryPath}, {'/home', '/home/docs'});
  });

  test('содержимое строки берётся по её пути, а не по тёзке из своего каталога', () async {
    final all = await () async {
      panel.setMarks({'/home/docs/notes.txt'});
      await pumpEventQueue();
      return panel.allTargets();
    }();
    final foreign = all.single;
    expect(foreign.path, '/home/docs/notes.txt');

    // В каталоге панели лежит свой `notes.txt` — и раньше читался именно он.
    expect(panel.entries.any((entry) => entry.name == 'notes.txt'), isTrue);
    expect(await panel.canWriteTo(foreign), isTrue, reason: 'спрошена чужая строка, а не тёзка');
    expect(panel.contentOf(foreign), isA<RemoteContent>(), reason: 'читать чужую строку есть чем');
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
    expect(panel.currentPath, '/home/docs');

    await panel.goUp();
    expect(panel.currentPath, '/home');
    expect(panel.currentEntry?.name, 'docs', reason: 'курсор встаёт на то, через что вошли');
  });

  test('в файл войти нельзя — он возвращается тому, кто просил', () async {
    final notes = panel.entries.firstWhere((entry) => entry.name == 'notes.txt');

    final blocked = await panel.enter(notes);

    expect(blocked?.name, 'notes.txt');
    expect(panel.currentPath, '/home');
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
    expect(docs.size, 90, reason: 'deep.txt и тёзка notes.txt');
    expect(panel.entries.length, before.length);
  });

  test('число держится за путь, а не за место в списке', () async {
    panel.measureDirectories();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pumpEventQueue();
    expect(panel.sizeOf('/home/docs'), 90);

    // Список сменился: другой каталог, другие строки, другой их порядок.
    await panel.openPath('/home/docs');
    await pumpEventQueue();

    // Число всё то же и всё про тот же каталог: строка ему не хозяйка, а
    // спрашивают о нём по пути — так его берут и ветви дерева.
    expect(panel.sizeOf('/home/docs'), 90);
    expect(panel.entries.any((entry) => entry.size == 90), isFalse, reason: 'чужой строке оно не досталось');

    await panel.openPath('/home');
    await pumpEventQueue();
    final docs = panel.entries.firstWhere((entry) => entry.name == 'docs');
    expect(docs.size, 90, reason: 'вернулись — число на месте, обход заново не нужен');
  });

  test('сортировка меняет порядок', () async {
    final names = panel.entries.map((entry) => entry.name).toList();

    await panel.sortBy(FsColumns.name);

    expect(panel.entries.map((entry) => entry.name), isNot(names));
  });

  test('чужая панель зеркалу безразлична', () async {
    await link.call(const OpenPath(PanelId.right, '/home/docs'));
    await pumpEventQueue();

    expect(panel.currentPath, '/home', reason: 'левая осталась где была');
  });
}
