import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Журнал работы: что в нём оказывается и чего в нём нет
/// (`docs/spec/operation-history.md`, §2 и §6).
void main() {
  late InMemoryTreeProvider provider;
  late CollectedJournal journal;
  const engine = TreeTransferEngine();

  setUp(() {
    journal = CollectedJournal();
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/one.txt', size: 1),
      FakeEntry.file('/home/docs/two.txt', size: 2),
      FakeEntry.directory('/dest'),
    ]);
  });

  Future<FsNode> nodeAt(String path) async => (await provider.resolvePath().run(path))!;
  Future<DirectoryNode> dirAt(String path) async => await nodeAt(path) as DirectoryNode;

  Future<void> copy(List<String> paths, String to) async => engine.copy().run(
    TransferParams([for (final path in paths) await nodeAt(path)], await dirAt(to), journal: journal),
  );

  Future<void> move(List<String> paths, String to) async => engine.move().run(
    TransferParams([for (final path in paths) await nodeAt(path)], await dirAt(to), journal: journal),
  );

  test('копия файла — одна запись о созданном', () async {
    await copy(['/home/notes.txt'], '/dest');

    expect(journal.paths, ['/dest/notes.txt']);
    final created = journal.only<Created>().single;
    expect(created.size, 10, reason: 'по нему отмена и сверит, не правили ли файл');
    expect(journal.obstacle, isNull);
  });

  test('копия каталога, которого не было, — тоже одна запись', () async {
    // Внутрь журнал не идёт: там всё создано этой работой, и отмена снесёт
    // дерево целиком (§6). Иначе предел журнала срабатывал бы ровно там, где
    // отмена нужнее всего.
    await copy(['/home/docs'], '/dest');

    expect(journal.paths, ['/dest/docs']);
    expect(journal.only<Created>().single.isDirectory, isTrue);
  });

  test('слияние в существующий каталог пишется поштучно', () async {
    provider.add(FakeEntry.directory('/dest/docs'));

    await copy(['/home/docs'], '/dest');

    // Сам каталог не записан: он был до работы, и удалять его при отмене
    // нельзя.
    expect(journal.paths, ['/dest/docs/one.txt', '/dest/docs/two.txt']);
  });

  test('перезапись необратима и говорит об этом', () async {
    provider.add(FakeEntry.file('/dest/notes.txt', size: 99));

    final operation = engine.copy();
    // Молча чужое не затирают: без ответа движок пропустил бы файл.
    operation.requests.listen((request) => request.respond(TransferAnswers.overwrite));
    await operation.run(TransferParams([await nodeAt('/home/notes.txt')], await dirAt('/dest'), journal: journal));

    expect(journal.only<Destroyed>().single.path, '/dest/notes.txt');
    expect(journal.only<Destroyed>().single.reason, 'overwritten');
  });

  test('перенос одного провайдера — один переезд', () async {
    await move(['/home/docs'], '/dest');

    final moved = journal.only<Moved>().single;
    expect(moved.from, '/home/docs');
    expect(moved.to, '/dest/docs');
    expect(journal.only<Created>(), isEmpty, reason: 'переезд — это не создание');
  });

  test('перенос слиянием отменить нельзя', () async {
    provider.add(FakeEntry.directory('/dest/docs'));

    await move(['/home/docs'], '/dest');

    expect(journal.obstacle, 'merged into an existing folder');
  });

  test('удаление в корзину помнит, куда положили', () async {
    await engine.remove().run(RemoveParams([await nodeAt('/home/notes.txt')], journal: journal));

    final trashed = journal.only<Trashed>().single;
    expect(trashed.from, '/home/notes.txt');
    expect(trashed.to, '/.Trash/notes.txt');
  });

  test('удаление мимо корзины необратимо', () async {
    await engine.remove().run(RemoveParams([await nodeAt('/home/docs')], toTrash: false, journal: journal));

    final destroyed = journal.only<Destroyed>().single;
    expect(destroyed.path, '/home/docs');
    expect(journal.entries.length, 1, reason: 'поштучно внутрь писать нечего: возвращать неоткуда');
  });

  test('создание каталога и переименование записываются', () async {
    await engine.makeDirectory().run(MakeDirectoryParams(await dirAt('/dest'), 'new', journal: journal));
    await engine.rename().run(RenameParams(await nodeAt('/home/notes.txt'), 'renamed.txt', journal: journal));

    expect(journal.only<Created>().single.path, '/dest/new');
    final moved = journal.only<Moved>().single;
    expect(moved.from, '/home/notes.txt');
    expect(moved.to, '/home/renamed.txt');
  });

  test('без журнала работа идёт как прежде', () async {
    await engine.copy().run(TransferParams([await nodeAt('/home/notes.txt')], await dirAt('/dest')));

    expect(await provider.resolvePath().run('/dest/notes.txt'), isNotNull);
    expect(journal.entries, isEmpty);
  });
}
