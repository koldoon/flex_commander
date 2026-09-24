import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_history/fc_history.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Откат по журналу (`docs/spec/operation-history.md`, §9).
void main() {
  late InMemoryTreeProvider provider;
  late ProviderRegistry registry;
  late CollectedJournal journal;
  const engine = TreeTransferEngine();

  setUp(() {
    journal = CollectedJournal();
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/one.txt', size: 1),
      FakeEntry.directory('/dest'),
    ]);
    registry = ProviderRegistry(root: provider);
  });

  Future<FsNode> nodeAt(String path) async => (await provider.resolvePath().run(path))!;
  Future<DirectoryNode> dirAt(String path) async => await nodeAt(path) as DirectoryNode;
  Future<bool> exists(String path) async => await provider.resolvePath().run(path) != null;

  /// Отменяет то, что записал журнал, — тем же способом, каким это делает
  /// команда: журнал уезжает доводами.
  Future<Operation<OperationInputs, void>> undoing() async =>
      UndoWork(strings: StringsRegistry(), registry: registry).operation();

  Future<void> undo({List<JournalEntry>? entries}) async {
    final work = await undoing();
    await work.run(
      OperationInputs(
        targets: const [],
        destination: null,
        editor: engine,
        options: {
          HistoryOperations.journal: [for (final entry in entries ?? journal.entries) entry.toMap()],
        },
        onFound: (_) {},
      ),
    );
  }

  test('откат копии удаляет ровно созданное', () async {
    await engine.copy().run(TransferParams([await nodeAt('/home/notes.txt')], await dirAt('/dest'), journal: journal));
    expect(await exists('/dest/notes.txt'), isTrue);

    await undo();

    expect(await exists('/dest/notes.txt'), isFalse);
    expect(await exists('/home/notes.txt'), isTrue, reason: 'источник копирование не трогало');
  });

  test('откат копии каталога сносит его целиком', () async {
    await engine.copy().run(TransferParams([await nodeAt('/home/docs')], await dirAt('/dest'), journal: journal));

    await undo();

    expect(await exists('/dest/docs'), isFalse);
    expect(await exists('/home/docs/one.txt'), isTrue);
  });

  test('откат переноса возвращает объект на место', () async {
    await engine.move().run(TransferParams([await nodeAt('/home/notes.txt')], await dirAt('/dest'), journal: journal));
    expect(await exists('/home/notes.txt'), isFalse);

    await undo();

    expect(await exists('/home/notes.txt'), isTrue);
    expect(await exists('/dest/notes.txt'), isFalse);
  });

  test('откат удаления достаёт объект из корзины под прежним именем', () async {
    await engine.remove().run(RemoveParams([await nodeAt('/home/notes.txt')], journal: journal));
    expect(await exists('/.Trash/notes.txt'), isTrue);

    await undo();

    expect(await exists('/home/notes.txt'), isTrue);
    expect(await exists('/.Trash/notes.txt'), isFalse);
  });

  test('откат переименования возвращает прежнее имя', () async {
    await engine.rename().run(RenameParams(await nodeAt('/home/notes.txt'), 'renamed.txt', journal: journal));

    await undo();

    expect(await exists('/home/notes.txt'), isTrue);
    expect(await exists('/home/renamed.txt'), isFalse);
  });

  test('откат создания каталога убирает его, пока он пуст', () async {
    await engine.makeDirectory().run(MakeDirectoryParams(await dirAt('/dest'), 'new', journal: journal));

    await undo();

    expect(await exists('/dest/new'), isFalse);
  });

  test('каталог, в котором появилось чужое, не сносится', () async {
    await engine.makeDirectory().run(MakeDirectoryParams(await dirAt('/dest'), 'new', journal: journal));
    provider.add(FakeEntry.file('/dest/new/чужое.txt', size: 1));

    await undo();

    expect(await exists('/dest/new'), isTrue, reason: 'в нём чужое — сносить нельзя');
    expect(await exists('/dest/new/чужое.txt'), isTrue);
  });

  test('того, чего уже нет, отмена не ищет и не роняется', () async {
    await engine.copy().run(TransferParams([await nodeAt('/home/notes.txt')], await dirAt('/dest'), journal: journal));
    // Кто-то убрал копию до нас — обычное дело.
    await provider.deleteTree(await nodeAt('/dest/notes.txt'));

    await undo();

    expect(await exists('/home/notes.txt'), isTrue);
  });

  test('изменившийся файл не удаляется молча', () async {
    await engine.copy().run(TransferParams([await nodeAt('/home/notes.txt')], await dirAt('/dest'), journal: journal));
    // Между работой и отменой файл правили: размер стал другим.
    provider.add(FakeEntry.file('/dest/notes.txt', size: 999));

    final work = await undoing();
    // Без ответа движок молчаливо пропускает — так и задумано.
    await work.run(
      OperationInputs(
        targets: const [],
        destination: null,
        editor: engine,
        options: {
          HistoryOperations.journal: [for (final entry in journal.entries) entry.toMap()],
        },
        onFound: (_) {},
      ),
    );

    expect(await exists('/dest/notes.txt'), isTrue, reason: 'правленое молча не удаляют');
  });
}
