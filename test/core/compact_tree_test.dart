import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/node_list.dart';
import 'package:flex_commander/core/tree_node_list.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сжатое дерево: цепочка каталогов с единственным подкаталогом — одной
/// строкой (`docs/spec/panel-view-compact-tree.md`).
void main() {
  List<FakeEntry> entries() => [
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/src'),
    FakeEntry.directory('/home/src/main'),
    FakeEntry.directory('/home/src/main/java'),
    FakeEntry.directory('/home/src/main/java/com'),
    FakeEntry.directory('/home/src/main/java/com/acme'),
    FakeEntry.file('/home/src/main/java/com/acme/A.java'),
    FakeEntry.file('/home/src/main/java/com/acme/B.java'),
    FakeEntry.directory('/home/one'),
    FakeEntry.file('/home/one/file.txt'),
    FakeEntry.directory('/home/deep'),
    FakeEntry.directory('/home/deep/.git'),
    FakeEntry.directory('/home/deep/inner'),
    FakeEntry.file('/home/deep/inner/x.txt'),
    FakeEntry.directory('/home/ln'),
    FakeEntry.link('/home/ln/to-src', '/home/src'),
    FakeEntry.directory('/home/pack'),
    FakeEntry.file('/home/pack/data.zip'),
  ];

  late InMemoryTreeProvider provider;

  setUp(() => provider = InMemoryTreeProvider(entries()));

  Future<DirectoryNode> dirAt(String path) async => (await provider.resolvePath().run(path))! as DirectoryNode;

  final declared = testColumnSorting();

  NodeListOrder order({bool includeHidden = false}) => NodeListOrder.of(
    const SortSpec(),
    includeHidden: includeHidden,
    column: declared.comparatorOf(const SortSpec().column),
  );

  /// Строки так, как их показывает сжатое дерево: отступ и подпись.
  Future<List<String>> rowsOf(TreeNodeList list, {bool includeHidden = false}) async {
    final rows = await list.read(order: order(includeHidden: includeHidden)).run(null);
    return [
      for (final node in rows)
        '${'  ' * node.level}${list.chainHeadOf(node).isEmpty ? node.name : '${list.chainHeadOf(node)}/${node.name}'}',
    ];
  }

  Future<TreeNodeList> compact({List<String> expanded = const [], bool compact = true}) async =>
      TreeNodeList(roots: [await dirAt('/home')], expanded: ['/home', ...expanded], compact: compact);

  test('цепочка раскрытых каталогов с единственным подкаталогом — одна строка', () async {
    final list = await compact(
      expanded: ['/home/src', '/home/src/main', '/home/src/main/java', '/home/src/main/java/com'],
    );

    final rows = await rowsOf(list);

    expect(rows.take(2), ['home', '  deep']);
    expect(rows, containsAllInOrder(['  src/main/java/com/acme']));
  });

  test('строка цепочки — самый глубокий каталог, его дети — на ступень глубже', () async {
    final list = await compact(
      expanded: [
        '/home/src',
        '/home/src/main',
        '/home/src/main/java',
        '/home/src/main/java/com',
        '/home/src/main/java/com/acme',
      ],
    );

    final rows = await list.read(order: order()).run(null);
    final chain = rows.singleWhere((node) => list.chainHeadOf(node).isNotEmpty);

    expect(chain.pathString, '/home/src/main/java/com/acme');
    expect(list.chainHeadOf(chain), 'src/main/java/com');
    expect(chain.level, 1, reason: 'глубина — начала цепочки');
    expect(chain.isOpen, isTrue);
    expect(rows.firstWhere((node) => node.name == 'A.java').level, 2);
  });

  test('каталог с единственным файлом не склеивается: файл стоит своей строкой', () async {
    final list = await compact(expanded: ['/home/one']);

    final rows = await rowsOf(list);

    expect(rows, containsAllInOrder(['  one', '    file.txt']));
  });

  test('корни не склеиваются', () async {
    final list = TreeNodeList(
      roots: [await dirAt('/home/src')],
      expanded: ['/home/src', '/home/src/main'],
      compact: true,
    );

    final rows = await rowsOf(list);

    expect(rows.first, 'src', reason: 'корень выбрали нарочно');
  });

  test('закрытый каталог завершает цепочку', () async {
    // Раскрыты `src` и `main`, а `java` — нет: дальше никто не заглядывал.
    final list = TreeNodeList(
      roots: [await dirAt('/home')],
      expanded: ['/home', '/home/src', '/home/src/main'],
      compact: true,
    );
    // Свежее раскрытие продолжило бы цепочку — проверяем само правило склейки
    // на уже прочитанном.
    await list.read(order: order()).run(null);
    list.collapse('/home/src/main/java');
    list.collapse('/home/src/main/java/com');

    final rows = await rowsOf(list);

    expect(rows, contains('  src/main/java'));
  });

  test('скрытый сосед рвёт цепочку, только когда скрытое показывают', () async {
    final list = await compact(expanded: ['/home/deep', '/home/deep/inner']);

    expect(await rowsOf(list), contains('  deep/inner'), reason: '.git не показан');
    expect(await rowsOf(list, includeHidden: true), containsAllInOrder(['  deep', '    .git', '    inner']));
  });

  test('ссылка цепочку не продолжает', () async {
    final list = await compact(expanded: ['/home/ln']);

    expect(await rowsOf(list), containsAllInOrder(['  ln', '    to-src']));
  });

  test('архив цепочку не продолжает, даже если его есть кому раскрыть', () async {
    final list = TreeNodeList(
      roots: [await dirAt('/home')],
      expanded: ['/home', '/home/pack'],
      compact: true,
      mounter: _ZipMounter(),
    );

    expect(await rowsOf(list), containsAllInOrder(['  pack', '    data.zip']));
  });

  test('поглощённый путь находит свою строку', () async {
    final list = await compact(
      expanded: ['/home/src', '/home/src/main', '/home/src/main/java', '/home/src/main/java/com'],
    );
    final rows = await list.read(order: order()).run(null);
    final chain = rows.singleWhere((node) => list.chainHeadOf(node).isNotEmpty);

    expect(list.shownAs('/home/src'), same(chain));
    expect(list.shownAs('/home/src/main/java'), same(chain));
    expect(list.shownAs('/home/src/main/java/com/acme'), isNull, reason: 'у самой строки свой путь');
  });

  test('перекладка порядка цепочки не теряет', () async {
    final list = await compact(
      expanded: ['/home/src', '/home/src/main', '/home/src/main/java', '/home/src/main/java/com'],
    );
    final rows = await list.read(order: order()).run(null);

    final again = list.reorder(rows, order());

    expect(again.where((node) => list.chainHeadOf(node).isNotEmpty), hasLength(1));
  });

  group('свежее раскрытие', () {
    test('раскрыли каталог — цепочка раскрывается до развилки', () async {
      final list = await compact();
      await rowsOf(list);

      list.expand('/home/src');
      final rows = await rowsOf(list);

      expect(rows, containsAllInOrder(['  src/main/java/com/acme', '    A.java', '    B.java']));
      expect(list.isExpanded('/home/src/main/java/com/acme'), isTrue);
    });

    test('свёрнутое человеком само не раскрывается', () async {
      final list = await compact();
      await rowsOf(list);
      list.expand('/home/src');
      await rowsOf(list);

      // Свернули строку цепочки — свернулся самый глубокий каталог.
      list.collapse('/home/src/main/java/com/acme');
      final rows = await rowsOf(list);

      expect(rows, contains('  src/main/java/com/acme'));
      expect(rows, isNot(contains('    A.java')));
    });
  });

  test('без флага строки те же, что у обычного дерева', () async {
    final expanded = ['/home/src', '/home/src/main', '/home/src/main/java'];
    final plain = TreeNodeList(roots: [await dirAt('/home')], expanded: ['/home', ...expanded]);
    final off = await compact(expanded: expanded, compact: false);

    expect(await rowsOf(off), await rowsOf(plain));
    final rows = await off.read(order: order()).run(null);
    expect(rows.every((node) => off.chainHeadOf(node).isEmpty), isTrue);
  });
}

/// Раскрывает архивы — то есть объявляет их ветвями. Монтировать в проверке
/// нечего: важно лишь, что архив ветвь, но не каталог.
class _ZipMounter implements BranchMounter {
  @override
  bool mountable(FsNode node) => node.name.endsWith('.zip');

  @override
  Future<DirectoryNode?> mount(FsNode node) async => null;
}
