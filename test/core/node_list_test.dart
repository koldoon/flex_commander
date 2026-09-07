import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/listing_cache.dart';
import 'package:flex_commander/core/node_list.dart';
import 'package:flutter_test/flutter_test.dart';

/// Провайдер, чтение которого не заканчивается, пока его не отпустят.
class _HeldProvider extends InMemoryTreeProvider {
  _HeldProvider(super.entries);

  final Completer<void> release = Completer<void>();

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    final inner = super.getDirectoryListing();
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      await release.future;
      op.checkCanceled();
      return op.delegate(inner, params);
    });
  }
}

/// Набор строк панели: первое звено цепочки — то, чем строки набираются
/// (`docs/spec/panel-node-list.md`, §3).
void main() {
  List<FakeEntry> entries() => [
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/docs'),
    FakeEntry.file('/home/notes.txt', size: 50),
    FakeEntry.file('/home/.hidden', size: 10),
  ];

  late InMemoryTreeProvider provider;
  late ListingCache cache;

  ListingCache freshCache() =>
      ListingCache(enabled: () => true, limit: () => 10, ttl: () => const Duration(minutes: 5));

  Future<DirectoryNode> home(TreeProvider source) async => (await source.resolvePath().run('/home'))! as DirectoryNode;

  setUp(() {
    provider = InMemoryTreeProvider(entries());
    cache = freshCache();
  });

  test('строки каталога собираются набором, а не панелью', () async {
    final list = DirectoryNodeList(await home(provider));

    final rows = await list.read(includeHidden: false).run(null);

    // Тот же список, что показывает панель: с «..» и без скрытых.
    expect(rows.map((node) => node.name), containsAll(['..', 'docs', 'notes.txt']));
    expect(rows.map((node) => node.name), isNot(contains('.hidden')));
  });

  test('скрытое приходит, если о нём попросили', () async {
    final list = DirectoryNodeList(await home(provider));

    final rows = await list.read(includeHidden: true).run(null);

    expect(rows.map((node) => node.name), contains('.hidden'));
  });

  test('корень у каталога один — он сам', () async {
    final dir = await home(provider);
    final list = DirectoryNodeList(dir);

    // У дерева и избранного корней будет несколько, и панель об этом не
    // узнает: она спрашивает строки, а не читает каталог.
    expect(list.roots, [dir]);
    expect(list.directory, dir);
  });

  test('запомненное отдаётся без чтения', () async {
    final list = DirectoryNodeList(await home(provider));
    expect(list.shown(cache, includeHidden: false), isNull, reason: 'ещё ничего не запоминали');

    final rows = await list.read(includeHidden: false).run(null);
    list.remember(cache, rows, includeHidden: false);

    expect(list.shown(cache, includeHidden: false)?.map((node) => node.name), rows.map((node) => node.name));
    // Со скрытыми это другой список, и подсказкой он не считается.
    expect(list.shown(cache, includeHidden: true), isNull);
  });

  test('отмена доходит до чтения источника', () async {
    final held = _HeldProvider(entries());
    final list = DirectoryNodeList(await home(held));
    final operation = list.read(includeHidden: false);

    operation.start(null);
    operation.cancel();
    held.release.complete();

    // Панель отменяет чтение, когда человек уже попросил другое: работа
    // обязана прерваться вся, а не только её обёртка.
    await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
  });
}
