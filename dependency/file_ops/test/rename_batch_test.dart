import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Работа переименования пачки: порядок, циклы и отказы
/// (`docs/spec/multi-rename.md`, §9 и §10).
void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a.txt', size: 1),
      FakeEntry.file('/home/b.txt', size: 1),
      FakeEntry.file('/home/c.txt', size: 1),
    ]);
  });

  Future<FsNode> nodeAt(String path) async => (await provider.resolvePath().run(path))!;

  /// Запускает работу теми же доводами, какими её зовёт окно.
  Future<void> rename(Map<String, String> renames, {OperationContext? context}) async {
    final targets = <FsNode>[];
    for (final path in renames.keys) {
      targets.add(await nodeAt(path));
    }
    await const RenameBatchWork().operation().run(
      OperationInputs(
        targets: targets,
        destination: null,
        editor: const TreeTransferEngine(),
        options: RenameBatch.of(renames).toOptions(),
        onFound: (_) {},
      ),
    );
  }

  Future<List<String>> namesInHome() async {
    final home = await nodeAt('/home') as DirectoryNode;
    final names = [for (final node in await provider.listChildren(home)) node.name]..sort();
    return names;
  }

  test('пачка переименовывается', () async {
    await rename({'/home/a.txt': 'один.txt', '/home/b.txt': 'два.txt'});

    expect(await namesInHome(), ['c.txt', 'два.txt', 'один.txt']);
  });

  test('сдвиг ряда идёт без временных имён', () async {
    // `a → b`, `b → c`, `c → d`: порядок находится сам, и ни одно имя не теряется.
    await rename({'/home/a.txt': 'b.txt', '/home/b.txt': 'c.txt', '/home/c.txt': 'd.txt'});

    expect(await namesInHome(), ['b.txt', 'c.txt', 'd.txt']);
  });

  test('обмен именами работает через временное имя', () async {
    await rename({'/home/a.txt': 'b.txt', '/home/b.txt': 'a.txt'});

    expect(await namesInHome(), ['a.txt', 'b.txt', 'c.txt'], reason: 'ни один файл не потерян');
  });

  test('имя, которое никто не освобождает, отказывает', () async {
    // Одна цель — отказ пробрасывается, а не спрашивается: окно возвращается
    // к форме.
    await expectLater(rename({'/home/a.txt': 'c.txt'}), throwsA(isA<FsError>()));

    expect(await namesInHome(), ['a.txt', 'b.txt', 'c.txt']);
  });

  test('цели, которой нет среди целей работы, не бывает', () async {
    // Пометку успели сменить: путь в парах есть, а узла нет — работа идёт
    // дальше по остальным.
    final targets = [await nodeAt('/home/a.txt')];
    await const RenameBatchWork().operation().run(
      OperationInputs(
        targets: targets,
        destination: null,
        editor: const TreeTransferEngine(),
        options: RenameBatch.of({'/home/a.txt': 'один.txt', '/home/нет.txt': 'два.txt'}).toOptions(),
        onFound: (_) {},
      ),
    );

    expect(await namesInHome(), ['b.txt', 'c.txt', 'один.txt']);
  });

  test('пустая заявка ничего не делает', () async {
    await const RenameBatchWork().operation().run(
      OperationInputs(
        targets: [await nodeAt('/home/a.txt')],
        destination: null,
        editor: const TreeTransferEngine(),
        options: const {},
        onFound: (_) {},
      ),
    );

    expect(await namesInHome(), ['a.txt', 'b.txt', 'c.txt']);
  });
}
