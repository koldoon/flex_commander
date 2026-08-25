import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Умения провайдера.
///
/// Смысл этих тестов не в том, что флаг выставлен, а в том, что он **не врёт**:
/// объявление проверяется поведением. Провайдер, объявивший лишнее, ломает не
/// себя, а того, кто ему поверил.
const editor = TreeTransferEngine();

void main() {
  late Directory temp;
  late String root;
  late String target;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_caps');
    root = await temp.resolveSymbolicLinks();

    await File(p.join(root, 'notes.txt')).writeAsString('текст');
    target = p.join(root, 'target');
    await Directory(target).create();

    provider = LocalTreeProvider(homePath: root, readInIsolate: false);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<FsNode> nodeAt(String name) async => (await provider.resolvePath().run(p.join(root, name)))!;

  Future<DirectoryNode> targetDir() async => (await provider.resolvePath().run(target))! as DirectoryNode;

  group('умения выводятся из интерфейсов', () {
    test('локальная ФС меняет дерево и отдаёт байты', () {
      // Не флаги, а сами примитивы: об этом соврать нельзя.
      expect(provider.canWrite, isTrue);
      expect(provider.canStream, isTrue);
    });

    test('источник только для чтения не умеет ни того, ни другого', () {
      final archive = InMemoryReadOnlyProvider([FakeEntry.directory('/home')]);

      expect(archive.canWrite, isFalse);
      expect(archive.canStream, isFalse);
    });
  });

  group('объявленное — правда', () {
    test('переименование работает', () async {
      expect(provider.capabilities.canRename, isTrue);

      expect(await provider.renameEntry(await nodeAt('notes.txt'), await targetDir(), 'notes.txt'), isTrue);
      expect(await File(p.join(target, 'notes.txt')).exists(), isTrue);
    });

    test('копия сохраняет дату изменения', () async {
      expect(provider.capabilities.preservesModified, isTrue);

      final modified = DateTime(2020, 1, 2, 3, 4, 5);
      File(p.join(root, 'notes.txt')).setLastModifiedSync(modified);

      await editor.copy().run(TransferParams([await nodeAt('notes.txt')], await targetDir()));

      expect(File(p.join(target, 'notes.txt')).lastModifiedSync(), modified);
    });

    test('чтение начинается с указанного места, а не с начала', () async {
      expect(provider.capabilities.canSeek, isTrue);

      final chunks = await (await provider.openRead(await nodeAt('notes.txt'), offset: 8)).toList();
      // «текст» в utf-8 — десять байт: с восьмого остаются два.
      expect([for (final chunk in chunks) ...chunk], hasLength(2));
    });

    test('пути настоящие: их можно отдать внешней программе', () async {
      expect(provider.capabilities.realFileSystem, isTrue);

      final node = await nodeAt('notes.txt');
      expect(await File(node.pathString).readAsString(), 'текст');
    });
  });

  test('умолчание осторожное: провайдер, который о себе не сказал, не умеет ничего', () {
    const unknown = ProviderCapabilities();

    expect(unknown.canRename, isFalse);
    expect(unknown.canSeek, isFalse);
    expect(unknown.preservesModified, isFalse);
    expect(unknown.realFileSystem, isFalse);
    // По одной работе за раз: медленно, зато чужой сервер цел.
    expect(unknown.maxConcurrency, 1);
  });
}
