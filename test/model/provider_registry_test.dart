import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/provider_registry.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake/in_memory_tree_provider.dart';

/// Вложенные источники: реестр фабрик по схеме и монтирование над узлом.
///
/// Провайдер архива ничего не знает о том, над чем он смонтирован, а локальная
/// ФС — о существовании архивов. Связывает их только реестр: это композиция,
/// а не наследование.
void main() {
  late InMemoryTreeProvider disk;
  late ProviderRegistry registry;
  late List<FsNode> mountedOver;

  List<FakeEntry> archiveEntries() => [
    FakeEntry.directory('/inner'),
    FakeEntry.file('/inner/doc.txt', content: [1, 2, 3]),
    FakeEntry.file('/readme.md', content: [4]),
  ];

  setUp(() {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/archive.arc', content: [0]),
      FakeEntry.file('/home/notes.txt', size: 3),
    ]);
    mountedOver = [];

    registry = ProviderRegistry(root: disk)..register('arc', (host) async {
      mountedOver.add(host);
      return InMemoryArchiveProvider(archiveEntries(), host);
    }, extensions: {'arc'});
  });

  Future<FsNode> nodeAt(String path) async => (await disk.resolvePath(path).result)!;

  group('чем открывать', () {
    test('расширение выбирает схему', () async {
      expect(registry.schemeFor(await nodeAt('/home/archive.arc')), 'arc');
    });

    test('незнакомое расширение не открывается ничем', () async {
      // Такой объект панель отдаст системе, а не станет читать как дерево.
      expect(registry.schemeFor(await nodeAt('/home/notes.txt')), isNull);
    });

    test('каталог не открывается как архив: в него и так входят', () async {
      expect(registry.schemeFor(await nodeAt('/home')), isNull);
    });

    test('незарегистрированная схема — отказ, а не пустое дерево', () async {
      final host = await nodeAt('/home/archive.arc');

      await expectLater(registry.mount('zip', host), throwsA(isA<FsError>()));
    });
  });

  group('монтирование', () {
    test('корень смонтированного провайдера стоит над узлом-хозяином', () async {
      final host = await nodeAt('/home/archive.arc');

      final mounted = await registry.mount('arc', host);

      expect(mountedOver.single, same(host));
      expect(mounted.rootDirectory.parent, same(host));
      // Наверх из архива — в каталог, где он лежит, а не в никуда.
      expect(mounted.rootDirectory.parentDirectory?.name, 'home');
    });

    test('путь внутри провайдера чужих имён не содержит', () async {
      final mounted = await registry.mount('arc', await nodeAt('/home/archive.arc'));
      final inner = (await mounted.resolvePath('/inner/doc.txt').result)!;

      // Провайдер архива знает только свою часть пути.
      expect(mounted.pathOf(inner), '/inner/doc.txt');
    });

    test('полный путь собирается через оба дерева', () async {
      final mounted = await registry.mount('arc', await nodeAt('/home/archive.arc'));
      final inner = (await mounted.resolvePath('/inner/doc.txt').result)!;

      // Ровно тот формат, который умеет разбирать NodePath.
      expect(inner.pathString, '/home/archive.arc:arc:/inner/doc.txt');
    });
  });

  group('разбор цепочки', () {
    test('путь проходит через оба провайдера', () async {
      final node = await registry.resolvePath('/home/archive.arc:arc:/inner/doc.txt').result;

      expect(node?.name, 'doc.txt');
      expect(node?.provider, isA<InMemoryArchiveProvider>());
      expect(node?.pathString, '/home/archive.arc:arc:/inner/doc.txt');
    });

    test('обычный путь — это цепочка из одной части', () async {
      final node = await registry.resolvePath('/home/notes.txt').result;

      expect(node?.name, 'notes.txt');
      expect(node?.provider, same(disk));
    });

    test('несуществующего внутри архива нет', () async {
      expect(await registry.resolvePath('/home/archive.arc:arc:/missing').result, isNull);
    });

    test('нет хозяина — нечего и монтировать', () async {
      expect(await registry.resolvePath('/home/missing.arc:arc:/inner').result, isNull);
    });

    test('чужая схема в начале пути — отказ', () async {
      // Второй корневой провайдер появится вместе с сетевым (5.6).
      await expectLater(registry.resolvePath('sftp:/host/dir').result, throwsA(isA<FsError>()));
    });
  });
}
