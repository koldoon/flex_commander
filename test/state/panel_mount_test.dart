import 'dart:async';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Панель во вложенном источнике.
///
/// Войти в архив — это открыть каталог чужого провайдера, и ничего больше:
/// панель следует за каталогом, а тот приносит провайдера с собой.
void main() {
  late InMemoryContentProvider disk;
  late ProviderRegistry registry;
  late PanelController panel;

  List<FakeEntry> archiveEntries() => [
    FakeEntry.directory('/inner'),
    FakeEntry.file('/inner/doc.txt', content: [1, 2, 3]),
    FakeEntry.file('/readme.md', content: [4]),
  ];

  /// [disposed] — тест закрывает панель сам, и второй раз её закрывать нельзя.
  Future<PanelController> panelOn(ProviderRegistry source, {String path = '/home', bool disposed = false}) async {
    final it = testPanel(provider: source.root, registry: source, settings: PanelSettings.defaults(path));
    if (!disposed) {
      addTearDown(it.dispose);
    }
    await it.openPath(path);
    return it;
  }

  setUp(() async {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/archive.arc', content: [0]),
      FakeEntry.file('/home/notes.txt', size: 3),
    ]);
    registry = ProviderRegistry(root: disk)..register(
      'arc',
      () => TaskOperation<FsNode, TreeProvider>((op, host) async => InMemoryArchiveProvider(archiveEntries(), host)),
      extensions: {'arc'},
    );
    panel = await panelOn(registry);
  });

  List<String> namesOf(PanelController of) => of.session.nodes.map((node) => node.name).toList();

  test('Enter на архиве показывает его содержимое', () async {
    panel.setCursorToName('archive.arc');

    expect(await panel.enterCurrent(), isNull);

    expect(namesOf(panel), containsAll(['inner', 'readme.md']));
    // Панель ушла в чужой провайдер, не зная о нём ничего.
    expect(panel.provider, isA<InMemoryArchiveProvider>());
  });

  test('файл, который открывать нечем, возвращается наверх', () async {
    panel.setCursorToName('notes.txt');

    // Им займётся система: панель не знает, что с ним делать.
    expect((await panel.enterCurrent())?.name, 'notes.txt');
    expect(panel.path, '/home');
  });

  test('путь панели показывает всю цепочку', () async {
    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();
    panel.setCursorToName('inner');
    await panel.enterCurrent();

    // Панель показывает путь **человеку**: архив в нём стоит на своём месте,
    // но схемой не размечен — её видно только внутри, у самого узла.
    expect(panel.path, '/home/archive.arc/inner');
    expect(panel.session.directory?.pathString, '/home/archive.arc:arc:/inner');
  });

  test('«..» из архива возвращает туда, где он лежит, и ставит на него курсор', () async {
    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();

    await panel.goUp();

    expect(panel.path, '/home');
    expect(panel.currentEntry?.name, 'archive.arc');
    expect(panel.provider, same(disk));
  });

  test('внутри архива менять нечем, и панель это признаёт', () async {
    expect(panel.editor, isNotNull);

    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();

    // Примитивов изменения у архива нет — команды выключатся сами.
    expect(panel.editor, isNull);
  });

  test('сохранённый путь внутри архива открывается снова', () async {
    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();
    panel.setCursorToName('inner');
    await panel.enterCurrent();

    final saved = panel.settings.path;
    expect(saved, '/home/archive.arc:arc:/inner');

    // Другая панель, тот же реестр: архив монтируется заново по строке пути.
    final restored = await panelOn(registry, path: saved);

    expect(namesOf(restored), contains('doc.txt'));
    expect(restored.provider, isA<InMemoryArchiveProvider>());
  });

  test('битый архив оставляет панель на месте и говорит почему', () async {
    final broken = ProviderRegistry(root: disk)..register(
      'arc',
      () => TaskOperation<FsNode, TreeProvider>((op, host) async => throw FsError(host.pathString, FsErrorKind.io)),
      extensions: {'arc'},
    );
    final it = await panelOn(broken);
    it.setCursorToName('archive.arc');

    expect(await it.enterCurrent(), isNull);

    expect(it.path, '/home');
    expect(it.phase, PanelPhase.error);
    expect(it.error?.kind, FsErrorKind.io);
  });

  test('копирование из архива наружу идёт потоком', () async {
    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();
    final inside = panel.session.nodes.firstWhere((node) => node.name == 'readme.md');
    final outside = (await disk.resolvePath().run('/home'))! as DirectoryNode;

    // Источник и приёмник разных провайдеров: ни переименования, ни копии
    // средствами провайдера — только байты.
    await const TreeTransferEngine().copy().run(TransferParams([inside], outside));

    expect(await disk.resolvePath().run('/home/readme.md'), isNotNull);
  });

  group('жизненный цикл', () {
    late List<InMemoryArchiveProvider> mounted;
    late ProviderRegistry tracking;

    setUp(() {
      mounted = [];
      tracking = ProviderRegistry(root: disk)..register(
        'arc',
        () => TaskOperation<FsNode, TreeProvider>((op, host) async {
          final provider = InMemoryArchiveProvider(archiveEntries(), host);
          mounted.add(provider);
          return provider;
        }),
        extensions: {'arc'},
      );
    });

    Future<PanelController> panelInArchive({bool disposed = false}) async {
      final it = await panelOn(tracking, disposed: disposed);
      it.setCursorToName('archive.arc');
      await it.enterCurrent();
      expect(it.provider, isA<InMemoryArchiveProvider>());
      return it;
    }

    test('уход из архива его закрывает', () async {
      final panel = await panelInArchive();
      expect(mounted.single.closed, isFalse);

      await panel.goUp();

      expect(mounted.single.closed, isTrue);
      expect(panel.provider, same(disk));
    });

    test('переходы внутри архива его не закрывают', () async {
      final panel = await panelInArchive();

      panel.setCursorToName('inner');
      await panel.enterCurrent();
      await panel.goUp();

      // Провайдер тот же — закрывать нечего.
      expect(mounted, hasLength(1));
      expect(mounted.single.closed, isFalse);
    });

    test('вход в другой архив закрывает прежний', () async {
      final panel = await panelInArchive();
      // Уходим наружу и заходим снова: это уже другой экземпляр.
      await panel.goUp();
      panel.setCursorToName('archive.arc');
      await panel.enterCurrent();

      expect(mounted, hasLength(2));
      expect(mounted.first.closed, isTrue);
      expect(mounted.last.closed, isFalse);
    });

    test('закрытие панели закрывает и архив', () async {
      final panel = await panelInArchive(disposed: true);

      panel.dispose();

      expect(mounted.single.closed, isTrue);
    });

    test('корневой провайдер не закрывается никогда', () async {
      final panel = await panelOn(tracking, disposed: true);

      panel.dispose();

      // Он один на приложение и панели не принадлежит.
      expect(await disk.resolvePath().run('/home'), isNotNull);
    });

    group('арендаторов больше одного', () {
      test('один архив в двух панелях — один экземпляр', () async {
        final first = await panelInArchive();
        final second = await panelInArchive();

        // Два экземпляра поверх одного файла разошлись бы состоянием:
        // записанное через один не увидел бы другой.
        expect(mounted, hasLength(1));
        expect(second.provider, same(first.provider));
        expect(tracking.mounted.single.tenants, 2);
      });

      test('одна панель ушла — вторая продолжает читать', () async {
        final first = await panelInArchive();
        final second = await panelInArchive();

        await first.goUp();

        expect(mounted.single.closed, isFalse, reason: 'вторая панель всё ещё в архиве');
        expect(namesOf(second), containsAll(['inner', 'readme.md']));

        await second.goUp();
        expect(mounted.single.closed, isTrue);
      });

      test('работа держит архив, из которого панель уже ушла', () async {
        final panel = await panelInArchive();

        // Так делает длительная команда: берёт аренду на всё время работы,
        // потому что панель за это время вправе уйти куда угодно.
        final work = panel.leaseProvider()!;
        await panel.goUp();

        // Раньше здесь провайдер закрывался, а работа продолжала из него
        // читать: «отпускает тот, кто уходит» держалось на модальном окне.
        expect(mounted.single.closed, isFalse);
        expect((await work.provider.resolvePath().run('/readme.md'))?.name, 'readme.md');

        await work.release();
        expect(mounted.single.closed, isTrue);
      });

      test('разобранный мимо панели путь закрывается тем, кто его просил', () async {
        // Приёмник у F5 задан строкой и может вести не туда, где панель стоит:
        // архив по дороге монтируется ради работы, и отпустить его больше
        // некому.
        final onDisk = await panelOn(tracking);
        final resolved = await onDisk.session.resolvePath().run('/home/archive.arc/inner');

        expect(resolved.node?.name, 'inner');
        expect(mounted.single.closed, isFalse);

        await resolved.release();
        expect(mounted.single.closed, isTrue);
        expect(tracking.mounted, isEmpty, reason: 'после работы не осталось ничего');
      });
    });

    test('неразобранный путь не оставляет архив открытым', () async {
      // Смонтировать пришлось, а узла внутри не нашлось.
      expect((await tracking.resolvePath().run(ResolvePathParams('/home/archive.arc:arc:/missing'))).node, isNull);

      expect(mounted.single.closed, isTrue);
      expect(tracking.mounted, isEmpty, reason: 'запись в таблице тоже не осталась');
    });

    test('разобранный путь оставляет архив открытым: им ещё пользуются', () async {
      final resolved = await tracking.resolvePath().run(ResolvePathParams('/home/archive.arc:arc:/inner'));

      expect(resolved.node, isNotNull);
      expect(mounted.single.closed, isFalse);

      // Держится он не сам по себе, а на аренде: отпустили — закрылся.
      await resolved.release();
      expect(mounted.single.closed, isTrue);
      expect(tracking.mounted, isEmpty);
    });
  });

  group('ход открытия', () {
    /// Реестр, у которого монтирование не кончается, пока его не отпустят.
    (ProviderRegistry, Completer<void>) slowRegistry() {
      final door = Completer<void>();
      final source = ProviderRegistry(root: disk)..register(
        'arc',
        () => TaskOperation<FsNode, TreeProvider>((op, host) async {
          op.message('Unpacking ${host.name}');
          await door.future;
          return InMemoryArchiveProvider(archiveEntries(), host);
        }),
        extensions: {'arc'},
      );
      return (source, door);
    }

    test('строка состояния называет то, что открывается сейчас', () async {
      final (source, door) = slowRegistry();
      final it = await panelOn(source);

      final opening = it.openPath('/home/archive.arc/inner');
      await pumpEventQueue();

      // «Loading…» ничего не говорит о том, чего ждать: путь может идти через
      // сервер и два архива.
      expect(it.statusText, 'Unpacking archive.arc');

      door.complete();
      expect(await opening, isTrue);
    });

    test('отмена во время разбора оставляет панель на месте', () async {
      final (source, door) = slowRegistry();
      final it = await panelOn(source);

      final opening = it.openPath('/home/archive.arc/inner');
      await pumpEventQueue();
      it.cancel();

      expect(await opening, isFalse);
      expect(it.path, '/home');
      expect(it.busy, isFalse);
      door.complete();
    });

    test('отмена во время монтирования по Enter прерывает открытие', () async {
      final (source, door) = slowRegistry();
      final it = await panelOn(source);
      it.setCursorToName('archive.arc');

      final entering = it.enterCurrent();
      await pumpEventQueue();
      expect(it.statusText, 'Unpacking archive.arc');

      it.cancel();
      await entering;

      expect(it.path, '/home');
      expect(it.busy, isFalse);
      door.complete();
    });
  });

  test('без реестра панель живёт в одном источнике, как раньше', () async {
    final plain = testPanel(provider: disk, settings: PanelSettings.defaults('/home'));
    addTearDown(plain.dispose);
    await plain.openPath('/home');
    plain.setCursorToName('archive.arc');

    // Открывать архив нечем: объект возвращается наверх как обычный файл.
    expect((await plain.enterCurrent())?.name, 'archive.arc');
  });
}
