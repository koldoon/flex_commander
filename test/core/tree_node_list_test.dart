import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/node_list.dart';
import 'package:flex_commander/core/tree_node_list.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дерево как набор строк: маппер разворачивает раскрытые ветви построчно
/// (`docs/spec/panel-node-list.md`, §3).
void main() {
  List<FakeEntry> entries() => [
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/lib'),
    FakeEntry.directory('/home/lib/src'),
    FakeEntry.file('/home/lib/src/panel.dart', size: 30),
    FakeEntry.file('/home/lib/app.dart', size: 20),
    FakeEntry.directory('/home/.git'),
    FakeEntry.file('/home/main.dart', size: 100),
  ];

  late InMemoryTreeProvider provider;

  setUp(() => provider = InMemoryTreeProvider(entries()));

  Future<DirectoryNode> dirAt(String path) async => (await provider.resolvePath().run(path))! as DirectoryNode;

  NodeListOrder order({bool includeHidden = false, SortSpec sort = const SortSpec()}) =>
      NodeListOrder.of(sort, includeHidden: includeHidden);

  Future<List<String>> rowsOf(TreeNodeList list, {NodeListOrder? with_}) async {
    final rows = await list.read(order: with_ ?? order()).run(null);
    return [for (final node in rows) '${'  ' * node.level}${node.name}'];
  }

  test('свёрнутое дерево — это один корень', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')]);

    expect(await rowsOf(list), ['home']);
  });

  test('раскрытая ветвь разворачивается построчно, с глубиной', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')])..expand('/home');

    // Каталоги выше файлов, и то и другое по имени — правило панели, а не
    // особый порядок дерева.
    expect(await rowsOf(list), ['home', '  lib', '  main.dart']);
  });

  test('раскрытие идёт вглубь', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')])..expand('/home');
    await rowsOf(list);
    list.expand('/home/lib');

    expect(await rowsOf(list), ['home', '  lib', '    src', '    app.dart', '  main.dart']);
  });

  test('строки знают, раскрыты ли они', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')])..expand('/home');

    final rows = await list.read(order: order()).run(null);

    expect(rows.first.isOpen, isTrue, reason: 'корень раскрыт');
    expect(rows.firstWhere((node) => node.name == 'lib').isOpen, isFalse);
    expect(rows.firstWhere((node) => node.name == 'main.dart').isOpen, isFalse, reason: 'файл не раскрывается');
  });

  test('свёрнутая ветвь уносит с собой всё, что под ней', () async {
    final list =
        TreeNodeList(roots: [await dirAt('/home')])
          ..expand('/home')
          ..expand('/home/lib');
    await rowsOf(list);

    list.collapse('/home/lib');

    expect(await rowsOf(list), ['home', '  lib', '  main.dart']);
    expect(list.isExpanded('/home/lib'), isFalse);
  });

  test('скрытое показывается по тому же правилу, что и в списке', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')])..expand('/home');

    expect(await rowsOf(list), isNot(contains('  .git')));
    expect(await rowsOf(list, with_: order(includeHidden: true)), contains('  .git'));
  });

  test('правило панели раскладывает каждую ветвь', () async {
    final list =
        TreeNodeList(roots: [await dirAt('/home')])
          ..expand('/home')
          ..expand('/home/lib');

    final byName = await rowsOf(list, with_: order(sort: const SortSpec(direction: SortDirection.descending)));

    // Перевёрнутое имя переворачивает порядок **внутри** ветвей, а не мешает
    // ветви с их содержимым: каталоги остаются выше файлов.
    expect(byName, ['home', '  lib', '    src', '    app.dart', '  main.dart']);
  });

  test('раскрытое можно назвать до того, как ветвь прочитана', () async {
    // Так приходит сохранённое: путями, и читать ради них дерево целиком
    // никто не станет.
    final list =
        TreeNodeList(roots: [await dirAt('/home')])
          ..expand('/home/lib')
          ..expand('/home');

    expect(await rowsOf(list), ['home', '  lib', '    src', '    app.dart', '  main.dart']);
  });

  test('новый порядок берётся без чтения', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')])..expand('/home');
    final rows = await list.read(order: order()).run(null);

    final again = list.reorder(rows, order(sort: const SortSpec(column: FsColumn.size)));

    // Ни одного чтения — только новый порядок: `main.dart` тяжелее, но
    // каталоги остаются выше файлов.
    expect([for (final node in again) node.name], ['home', 'lib', 'main.dart']);
  });

  test('раскрытое помнится путями — их и сохранять', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')], expanded: ['/home', '/home/lib']);

    expect(await rowsOf(list), ['home', '  lib', '    src', '    app.dart', '  main.dart']);
    expect(list.expandedPaths, {'/home', '/home/lib'});
  });

  test('исчезнувшее раскрытым не станет', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')], expanded: ['/home', '/home/missing'])..expand('/home');

    // Путь, которого больше нет, просто не встретится: молча, без отказа.
    expect(await rowsOf(list), ['home', '  lib', '  main.dart']);
  });

  test('корней бывает несколько, и строки идут подряд', () async {
    final list = TreeNodeList(roots: [await dirAt('/home/lib'), await dirAt('/home/.git')])..expand('/home/lib');

    // Избранное и находки — это набор корней; список от этого не перестаёт
    // быть одним списком. Корень с точкой в имени при этом остаётся: его
    // выбрали нарочно.
    expect(await rowsOf(list), ['lib', '  src', '  app.dart', '.git']);
  });

  test('каталог операции — тот, где стоит курсор', () async {
    final list = TreeNodeList(roots: [await dirAt('/home')])..expand('/home');
    final rows = await list.read(order: order()).run(null);

    final lib = rows.firstWhere((node) => node.name == 'lib');
    expect(list.currentPathFor(lib), '/home', reason: 'ветвь лежит в своём каталоге');

    // Корень ни в чём не лежит: каталога он не называет, и панель остаётся
    // там, где стояла (`docs/spec/panel-view-tree.md`, §3).
    expect(list.currentPathFor(rows.first), isNull);
    expect(list.currentPathFor(null), isNull);
  });
}
