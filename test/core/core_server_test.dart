import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_panels/fc_panels.dart';

/// Провайдер с медленным чтением каталога.
///
/// Нужен там, где важно, что список идёт **не мгновенно**: пока он идёт,
/// человек успевает нажать ещё.
class _SlowListingProvider extends InMemoryTreeProvider {
  _SlowListingProvider(super.entries);

  bool slow = false;

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    if (!slow) {
      return super.getDirectoryListing();
    }
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return super.getDirectoryListing().run(params);
    });
  }
}

/// Ядро через границу: то же самое приложение, но разговором.
///
/// Проверяется здесь не панель — её проверяет весь остальной прогон, — а то,
/// что через язык границы проходит всё, что панель умеет, и что наружу
/// уезжают значения, а не живое.
void main() {
  late _SlowListingProvider provider;
  late CoreServer core;
  late Link link;
  late List<CoreEvent> heard;
  late StreamSubscription<CoreEvent> listening;

  PanelSession sessionFor(String path) => PanelSession(
    settings: PanelSettings.defaults(path),
    registry: ProviderRegistry(root: provider),
    editor: const TreeTransferEngine(),
  );

  setUp(() {
    provider = _SlowListingProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/deep.txt', size: 40),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.txt', size: 20),
    ])..home = '/home';

    core = CoreServer(left: sessionFor('/home'), right: sessionFor('/home'));
    link = LoopbackLink(core);
    heard = [];
    listening = link.events.listen(heard.add);
  });

  tearDown(() async {
    await listening.cancel();
    await link.dispose();
    await core.dispose();
  });

  /// Список левой панели — последний, о котором рассказало ядро.
  PanelListing? lastListing([PanelId panel = PanelId.left]) =>
      heard.whereType<PanelListed>().where((event) => event.panel == panel).lastOrNull?.listing;

  PanelState? lastState([PanelId panel = PanelId.left]) =>
      heard.whereType<PanelChanged>().where((event) => event.panel == panel).lastOrNull?.state;

  test('просьба к убранной панели уходит в пустоту, а не роняет ядро', () async {
    // Экран мог отправить её до того, как узнал о закрытии, — обычный ход дела.
    // Развёртка `_panels[panel]!` превращала это в поломку ядра, и та
    // приезжала на экран без единой строки о месте.
    await link.call(const ClosePanel(PanelId.right));

    // Отвечает, а не молчит: ждущий без ответа висел бы вечно.
    expect(await link.call(const OpenPath(PanelId.right, '/home')), isA<CoreDone>());
    expect(await link.call(const Reload(PanelId.right)), isA<CoreDone>());
    expect(await link.call(const AskHistory(PanelId.right)), isA<CoreDone>());

    // Живая панель при этом отвечает как обычно.
    expect(await link.call(const OpenPath(PanelId.left, '/home')), isA<CoreOpened>());
  });

  group('рукопожатие', () {
    test('первое слово ядра — что у него есть прямо сейчас', () async {
      final ready = await link.call(const Handshake()) as CoreReady;

      expect(ready.states.keys, containsAll(const [PanelId.left, PanelId.right]));
      expect(ready.listings[PanelId.left]!.entries, isEmpty, reason: 'каталог ещё не открывали');
    });
  });

  group('каталог', () {
    test('открытый каталог приезжает списком значений', () async {
      final opened = await link.call(const OpenPath(PanelId.left, '/home')) as CoreOpened;

      expect(opened.opened, isTrue);
      final listing = lastListing()!;
      expect(listing.entries.map((entry) => entry.name), containsAll(['docs', 'notes.txt', 'report.txt']));
      expect(listing.entries.first.kind, EntryKind.parent, reason: '«..» всегда первая');
      expect(listing.entries.first.path, isEmpty, reason: '«..» показывает чужой каталог — адреса у неё нет');
      expect(
        listing.entries.first.realPath,
        '/',
        reason: 'а вот вне приложения «..» значит вполне настоящий каталог — тот, куда ведёт',
      );
    });

    test('в списке едут значения, а не узлы', () async {
      await link.call(const OpenPath(PanelId.left, '/home'));

      final notes = lastListing()!.entries.firstWhere((entry) => entry.name == 'notes.txt');
      expect(notes.size, 10);
      expect(notes.path, '/home/notes.txt');
      expect(notes.kind, EntryKind.file);
      // Ничего живого: значение не знает ни про узел, ни про источник.
      expect(notes, isA<FileEntry>());
    });

    test('состояние едет вместе со списком и знает его номер', () async {
      await link.call(const OpenPath(PanelId.left, '/home'));

      final state = lastState()!;
      expect(state.currentPath, '/home');
      expect(state.phase, PanelPhase.idle);
      expect(state.generation, lastListing()!.generation);
      expect(state.source.scheme, provider.scheme);
      expect(state.source.canWrite, isTrue, reason: 'подставное дерево умеет запись');
    });

    test('несуществующий путь — отказ с причиной, а не пустой список', () async {
      await link.call(const OpenPath(PanelId.left, '/home'));
      final before = lastListing()!.entries.length;

      final opened = await link.call(const OpenPath(PanelId.left, '/nowhere')) as CoreOpened;

      expect(opened.opened, isFalse);
      expect(lastListing()!.entries, hasLength(before), reason: 'панель осталась там, где была');
    });

    test('вход в каталог даёт новый список с новым номером', () async {
      await link.call(const OpenPath(PanelId.left, '/home'));
      final listing = lastListing()!;
      final docs = listing.entries.firstWhere((entry) => entry.name == 'docs');

      final entered = await link.call(
        OpenEntry(PanelId.left, EntryRef.inPanel(PanelId.left, docs.id, path: docs.path)),
      );

      expect((entered as CoreEntered).entry, isNull, reason: 'вошли');
      expect(lastState()!.currentPath, '/home/docs');
      expect(lastListing()!.generation, greaterThan(listing.generation));
      expect(lastListing()!.entries.map((entry) => entry.name), contains('deep.txt'));
    });

    test('заявка на строку, которой больше нет, не исполняется', () async {
      await link.call(const OpenPath(PanelId.left, '/home'));

      // Ни личности, ни пути — подтвердить нечем, и это честный отказ, а не
      // вход в произвольную строку.
      final entered = await link.call(
        OpenEntry(PanelId.left, const EntryRef.inPanel(PanelId.left, 99999, path: '/home/gone.txt')),
      );

      expect((entered as CoreEntered).entry, isNull);
      expect(lastState()!.currentPath, '/home', reason: 'никуда не пошли');
    });

    test('список вырос — заявка на строку всё равно исполняется', () async {
      // Ровно то, что ломалось живьём на растущем списке находок: ссылка
      // строилась при нажатии, а к ядру приезжала, когда номер списка уже
      // сменился (`docs/spec/client-server.md`, §5.5а).
      await link.call(const OpenPath(PanelId.left, '/home'));
      final docs = lastListing()!.entries.firstWhere((entry) => entry.name == 'docs');
      final was = lastListing()!.generation;

      provider.add(FakeEntry.file('/home/fresh.txt', size: 1));
      await link.call(const Reload(PanelId.left));
      expect(lastListing()!.generation, greaterThan(was), reason: 'стенд ни о чём без нового списка');

      final entered = await link.call(
        OpenEntry(PanelId.left, EntryRef.inPanel(PanelId.left, docs.id, path: docs.path)),
      );

      expect((entered as CoreEntered).entry, isNull, reason: 'вошли');
      expect(lastState()!.currentPath, '/home/docs');
    });

    test('в файл войти нельзя — он и приезжает обратно', () async {
      await link.call(const OpenPath(PanelId.left, '/home'));
      final listing = lastListing()!;
      final notes = listing.entries.firstWhere((entry) => entry.name == 'notes.txt');

      final entered =
          await link.call(OpenEntry(PanelId.left, EntryRef.inPanel(PanelId.left, notes.id, path: notes.path)))
              as CoreEntered;

      expect(entered.entry?.name, 'notes.txt');
      expect(lastState()!.currentPath, '/home', reason: 'панель осталась на месте');
    });

    test('наверх — тем же разговором', () async {
      await link.call(const OpenPath(PanelId.left, '/home/docs'));

      await link.call(const GoUp(PanelId.left));

      expect(lastState()!.currentPath, '/home');
      expect(lastState()!.cursorIndex, greaterThanOrEqualTo(0));
    });
  });

  group('курсор и пометка', () {
    setUp(() => link.call(const OpenPath(PanelId.left, '/home')));

    test('«стою вот здесь» — факт, и ядро его принимает', () async {
      // Курсор принадлежит экрану: сюда едет факт, а не просьба, и ответа на
      // него нет (`docs/spec/client-server.md`, §5.6).
      link.tell(const CursorAt(PanelId.left, '/home/report.txt'));
      await pumpEventQueue();

      expect(core.session(PanelId.left).currentNode?.name, 'report.txt');
    });

    test('строки с таким путём нет — ядро держит прежнюю', () async {
      link.tell(const CursorAt(PanelId.left, '/home/report.txt'));
      await pumpEventQueue();

      link.tell(const CursorAt(PanelId.left, '/home/нет-такого'));
      await pumpEventQueue();

      expect(core.session(PanelId.left).currentNode?.name, 'report.txt', reason: 'место себе не выдумываем');
    });

    test('пометка едет путями', () async {
      link.tell(const SetMarks(PanelId.left, {'/home/notes.txt', '/home/report.txt'}, 1));
      await pumpEventQueue();

      expect(lastState()!.markedPaths, {'/home/notes.txt', '/home/report.txt'});
      expect(lastState()!.markedSize, 30);
    });

    test('цели едут значениями, и в них есть помеченное из соседней ветви', () async {
      link.tell(const SetMarks(PanelId.left, {'/home/notes.txt', '/home/docs/deep.txt'}, 1));
      await pumpEventQueue();

      final reply = await link.call(const ListTargets(PanelId.left, under: null)) as CoreEntries;

      expect(reply.entries.map((entry) => entry.name), containsAll(['notes.txt', 'deep.txt']));
      expect(
        {for (final entry in reply.entries) entry.directoryPath},
        {'/home', '/home/docs'},
        reason: 'каталог приезжает значением — резать путь строкой не надо',
      );
    });

    test('цели дожидаются пометки, которую ещё разбирают', () async {
      // Чужой путь панель никогда не показывала: ядро разбирает его само, и
      // просьба, пришедшая в тот же миг, обязана дождаться
      // (`docs/spec/operation-targets.md`, §3).
      link.tell(const SetMarks(PanelId.left, {'/home/docs/deep.txt'}, 1));

      final reply = await link.call(const ListTargets(PanelId.left, under: null)) as CoreEntries;

      expect(reply.entries.map((entry) => entry.name), ['deep.txt']);
    });

    test('без пометки цель — названная строка, а не курсор ядра', () async {
      // Курсор принадлежит экрану, и строку называет спрашивающий. Здесь это
      // видно прямо: курсор в ядре стоит в другом месте, а ответ — про
      // названную строку (`docs/spec/client-server.md`, §5.6).
      final listing = lastListing()!;
      final notes = listing.entries.firstWhere((entry) => entry.name == 'notes.txt');
      link.tell(const CursorAt(PanelId.left, ''));
      await pumpEventQueue();

      final reply =
          await link.call(ListTargets(PanelId.left, under: EntryRef.inPanel(PanelId.left, notes.id, path: notes.path)))
              as CoreEntries;

      expect(reply.entries.map((entry) => entry.name), ['notes.txt']);
    });

    test('названной строки нет — целей нет, и ядро не подставляет свою', () async {
      final reply =
          await link.call(const ListTargets(PanelId.left, under: EntryRef.inPanel(PanelId.left, 99, path: '/nope')))
              as CoreEntries;

      expect(reply.entries, isEmpty);
    });

    test('пометка, поставленная во время чтения, не пропадает', () async {
      // Так помечают в дереве: курсор ушёл в соседнюю ветвь — каталог панели
      // тихо подтягивается, — а `Space` в это время жмут дальше. Список
      // приходит и не вправе отменить сделанное после того, как он был
      // заказан (`docs/spec/operation-targets.md`, §3).
      provider.slow = true;
      link.tell(const FollowCursor(PanelId.left, '/home/docs', 'deep.txt'));
      // Пометка ставится, **пока список идёт**: чтение уже заказано, а человек
      // всё ещё жмёт `Space`.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      link.tell(const SetMarks(PanelId.left, {'/home/notes.txt'}, 1));
      await pumpEventQueue();
      expect(lastState()!.markedPaths, {'/home/notes.txt'}, reason: 'пометка встала сразу');

      // Список приходит позже — и пометку, поставленную после его заказа, не
      // трогает.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await pumpEventQueue();

      expect(lastState()!.currentPath, '/home/docs');
      expect(lastState()!.markedPaths, {'/home/notes.txt'});
    });

    test('пометки, посланные подряд, применяются по порядку', () async {
      link.tell(const SetMarks(PanelId.left, {'/home/docs/deep.txt'}, 1));
      link.tell(const SetMarks(PanelId.left, {'/home/docs/deep.txt', '/home/notes.txt'}, 2));
      link.tell(const SetMarks(PanelId.left, {'/home/docs/deep.txt', '/home/notes.txt', '/home/report.txt'}, 3));
      await pumpEventQueue();

      expect(lastState()!.markedPaths, {'/home/docs/deep.txt', '/home/notes.txt', '/home/report.txt'});
    });

    test('пометка приезжает целиком, а не по одному объекту', () async {
      // Найдено трассировкой на живом. Пометка собиралась поштучно —
      // `clear` и по `add` на путь, — и каждое изменение уносило стейт: на
      // десять помеченных десяток событий, и первое из них с **пустым**
      // набором. Нажатие, пришедшееся на этот миг, собирало новый набор поверх
      // пустого — так и пропадало помеченное (`docs/spec/client-server.md`,
      // §5.5).
      heard.clear();
      link.tell(const SetMarks(PanelId.left, {'/home/notes.txt', '/home/report.txt', '/home/docs'}, 4));
      await pumpEventQueue();

      final counts = [
        for (final event in heard)
          if (event is PanelChanged && event.panel == PanelId.left && event.state.marksSeq == 4)
            event.state.markedPaths.length,
      ];

      // Событий может быть и несколько — обход размеров помеченного каталога
      // шлёт свои, — но ни одно не вправе унести **недособранную** пометку.
      expect(counts, isNotEmpty);
      expect(counts, everyElement(3), reason: 'пометка уезжает целой, а не по дороге');
    });

    test('номер заявки не появляется раньше самой пометки', () async {
      // Пока ядро разбирает чужой путь, случается всё остальное: обход
      // размеров, движение курсора, приход списка. Каждое такое событие уносит
      // стейт — и если номер заявки уже стоит, а пометка ещё нет, зеркало
      // примет это за свежее подтверждение и отберёт у себя помеченное
      // (`docs/spec/client-server.md`, §5.5).
      link.tell(const SetMarks(PanelId.left, {'/home/docs/deep.txt'}, 7));
      link.tell(const CursorAt(PanelId.left, '/home/report.txt'));
      await pumpEventQueue();

      final states = [
        for (final event in heard)
          if (event is PanelChanged && event.panel == PanelId.left) event.state,
      ];
      expect(
        states.where((state) => state.marksSeq == 7).map((state) => state.markedPaths),
        everyElement(isNotEmpty),
        reason: 'номер седьмой заявки не едет с пустой пометкой',
      );
      expect(lastState()!.markedPaths, {'/home/docs/deep.txt'});
    });

    test('опоздавшая заявка на пометку не отменяет свежую', () async {
      link.tell(const SetMarks(PanelId.left, {'/home/docs/deep.txt'}, 1));
      link.tell(const SetMarks(PanelId.left, {'/home/notes.txt', '/home/report.txt'}, 2));
      await pumpEventQueue();

      expect(lastState()!.markedPaths, {'/home/notes.txt', '/home/report.txt'});
      expect(lastState()!.marksSeq, 2);
    });

    test('пометка переживает перечитывание каталога', () async {
      link.tell(const SetMarks(PanelId.left, {'/home/notes.txt'}, 1));
      await pumpEventQueue();

      await link.call(const Reload(PanelId.left));

      expect(lastState()!.markedPaths, {'/home/notes.txt'});
    });
  });

  group('вид', () {
    setUp(() => link.call(const OpenPath(PanelId.left, '/home')));

    test('сортировка меняет порядок и даёт новый номер списка', () async {
      final before = lastListing()!;
      final names = before.entries.map((entry) => entry.name).toList();

      await link.call(
        const Arrange(PanelId.left, sort: SortSpec(column: FsColumns.name, direction: SortDirection.descending)),
      );

      final after = lastListing()!;
      expect(after.generation, greaterThan(before.generation));
      expect(after.entries.map((entry) => entry.name), isNot(names));
    });

    test('скрытые показываются по просьбе', () async {
      provider.add(FakeEntry.file('/home/.secret', size: 1));
      await link.call(const Reload(PanelId.left));
      expect(lastListing()!.entries.map((entry) => entry.name), isNot(contains('.secret')));

      await link.call(const Arrange(PanelId.left, showHidden: true));

      expect(lastListing()!.entries.map((entry) => entry.name), contains('.secret'));
      expect(lastState()!.showHidden, isTrue);
    });
  });

  group('размеры', () {
    test('посчитанные каталоги едут числами, а не списком заново', () async {
      await link.call(const OpenPath(PanelId.left, '/home'));
      final listedBefore = heard.whereType<PanelListed>().length;

      link.tell(const MeasureDirectories(PanelId.left));
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pumpEventQueue();

      final sized = heard.whereType<PanelSized>().toList();
      expect(sized, isNotEmpty, reason: 'о посчитанном рассказывают');
      // Событие говорит **факт**: вот этот каталог изменился. Адрес — путь:
      // размер принадлежит каталогу, а не месту в списке, а список под ним
      // меняется на каждый шаг курсора по дереву.
      expect(sized.last.paths, contains('/home/docs'));

      // Значение спрашивают — и получают то, какое ядро знает сейчас.
      final reply = await link.call(const AskSizes(PanelId.left, ['/home/docs']));
      expect((reply as CoreSizes).sizes['/home/docs'], 40, reason: 'внутри docs лежит сорок байт');
      expect(heard.whereType<PanelListed>().length, listedBefore, reason: 'список ради восьми байт заново не возят');
    });

    test('посчитанное спрашивают по путям — в том числе о чужих ветвях', () async {
      await link.call(const OpenPath(PanelId.left, '/home'));

      link.tell(const MeasureDirectories(PanelId.left));
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pumpEventQueue();

      // Так спрашивает дерево: оно видит сразу несколько ветвей, а список
      // панели знает только текущий каталог.
      final reply = await link.call(const AskSizes(PanelId.left, ['/home/docs', '/home/missing']));

      expect(reply, isA<CoreSizes>());
      expect((reply as CoreSizes).sizes, {'/home/docs': 40}, reason: 'непосчитанного в ответе нет');
    });
  });

  group('две панели', () {
    test('панели независимы: своё состояние у каждой', () async {
      await link.call(const OpenPath(PanelId.left, '/home/docs'));
      await link.call(const OpenPath(PanelId.right, '/home'));

      expect(lastState(PanelId.left)!.currentPath, '/home/docs');
      expect(lastState(PanelId.right)!.currentPath, '/home');
      expect(lastListing(PanelId.right)!.entries.map((entry) => entry.name), contains('notes.txt'));
    });
  });
}
