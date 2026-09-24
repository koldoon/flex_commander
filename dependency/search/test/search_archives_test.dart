import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поиск заходит в архивы (`docs/spec/file-search.md`, §12).
void main() {
  late InMemoryContentProvider disk;
  late ProviderRegistry registry;
  late int mounts;

  /// Что лежит внутри архива: имя для отбора по имени и байты для отбора по
  /// содержимому.
  List<FakeEntry> inside() => [
    FakeEntry.directory('/docs'),
    FakeEntry.file('/docs/buried.txt', content: utf8.encode('заметка про кота')),
    FakeEntry.file('/readme.md', content: utf8.encode('ничего интересного')),
  ];

  setUp(() {
    mounts = 0;
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/deep'),
      FakeEntry.file('/home/deep/box.arc', content: [0]),
      FakeEntry.file('/home/notes.txt', content: utf8.encode('просто файл')),
    ]);
    registry = ProviderRegistry(root: disk)..register(
      'arc',
      () => TaskOperation<FsNode, TreeProvider>((op, host) async {
        mounts++;
        return InMemoryArchiveProvider(inside(), host);
      }),
      extensions: {'arc'},
    );
  });

  Future<DirectoryNode> home() async => await disk.resolvePath().run('/home') as DirectoryNode;

  Future<List<String>> search(SearchQuery query) async {
    final run = SearchRun.from(await home(), onFound: (_) {}, registry: registry);
    final found = await run.run(query);
    return found.map((node) => node.pathString).toList();
  }

  test('без флажка внутрь архива обход не заходит', () async {
    final found = await search(const SearchQuery(mask: '*.txt'));

    expect(found, ['/home/notes.txt']);
    expect(registry.mounted, isEmpty, reason: 'и монтировать было незачем');
  });

  test('с флажком файл внутри архива находится по имени', () async {
    final found = await search(const SearchQuery(mask: '*.txt', archives: true));

    expect(found, containsAll(['/home/notes.txt', '/home/deep/box.arc:arc:/docs/buried.txt']));
  });

  test('находка несёт архив звеном пути, а не выдуманным каталогом', () async {
    final found = await search(const SearchQuery(mask: 'buried.txt', archives: true));

    expect(found.single, '/home/deep/box.arc:arc:/docs/buried.txt');
  });

  test('с флажком ищется и по содержимому внутри архива', () async {
    final found = await search(const SearchQuery(mask: '', content: 'кота', archives: true));

    expect(found.single, '/home/deep/box.arc:arc:/docs/buried.txt');
  });

  test('после обхода открытых архивов не остаётся', () async {
    await search(const SearchQuery(mask: '*.txt', archives: true));

    expect(mounts, 1, reason: 'архив открыт один раз');
    expect(registry.mounted, isEmpty, reason: 'и отпущен, как обход из него вышел');
  });

  test('битый архив обход переживает', () async {
    registry = ProviderRegistry(root: disk)..register(
      'arc',
      () => TaskOperation<FsNode, TreeProvider>(
        (op, host) async => throw const FsError('box.arc', FsErrorKind.notSupported),
      ),
      extensions: {'arc'},
    );

    final found = await search(const SearchQuery(mask: '*.txt', archives: true));

    expect(found, ['/home/notes.txt'], reason: 'внешнее дерево досмотрено до конца');
    expect(registry.mounted, isEmpty);
  });

  test('без реестра источников флажок ничего не меняет', () async {
    // Сборка без архивных модулей: открывать нечем.
    final run = SearchRun.from(await home(), onFound: (_) {});
    final found = await run.run(const SearchQuery(mask: '*.txt', archives: true));

    expect(found.map((node) => node.pathString), ['/home/notes.txt']);
  });

  test('глубже предела вложения обход не идёт', () async {
    // Архив внутри архива — по тому же флажку, но с пределом: иначе один криво
    // собранный `.tar` уводит обход в часы работы (§12.4).
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/outer.arc', content: [0]),
    ]);
    registry = ProviderRegistry(root: disk)..register(
      'arc',
      () => TaskOperation<FsNode, TreeProvider>((op, host) async {
        mounts++;
        // Внутри внешнего — ещё один архив и файл рядом с ним.
        return host.name == 'outer.arc'
            ? InMemoryArchiveProvider([
              FakeEntry.file('/inner.arc', content: [0]),
              FakeEntry.file('/first.txt', content: utf8.encode('верхний слой')),
            ], host)
            : InMemoryArchiveProvider([FakeEntry.file('/second.txt', content: utf8.encode('нижний слой'))], host);
      }),
      extensions: {'arc'},
    );

    final found = await search(const SearchQuery(mask: '*.txt', archives: true));

    expect(found, ['/home/outer.arc:arc:/first.txt'], reason: 'один уровень вложения — один архив');
    expect(mounts, 1);
  });

  test('с поднятым пределом разворачивается и архив в архиве', () async {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/outer.arc', content: [0]),
    ]);
    registry = ProviderRegistry(root: disk)..register(
      'arc',
      () => TaskOperation<FsNode, TreeProvider>((op, host) async {
        mounts++;
        return host.name == 'outer.arc'
            ? InMemoryArchiveProvider([
              FakeEntry.file('/inner.arc', content: [0]),
            ], host)
            : InMemoryArchiveProvider([FakeEntry.file('/second.txt', content: utf8.encode('нижний слой'))], host);
      }),
      extensions: {'arc'},
    );
    SearchRun.archiveDepth = 2;
    addTearDown(() => SearchRun.archiveDepth = 1);

    final found = await search(const SearchQuery(mask: '*.txt', archives: true));

    expect(found.single, contains('second.txt'));
    expect(registry.mounted, isEmpty, reason: 'оба отпущены');
  });
}
