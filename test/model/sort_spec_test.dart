import 'package:flex_commander/model/panel/column_spec.dart';
import 'package:flex_commander/model/panel/sort_spec.dart';
import 'package:flex_commander/model/tree/file_type.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake/in_memory_tree_provider.dart';

void main() {
  late InMemoryTreeProvider provider;
  late DirectoryNode root;

  setUp(() {
    provider = InMemoryTreeProvider();
    root = provider.rootDirectory;
  });

  FileNode file(String name, {int size = 0, DateTime? modified}) =>
      FileNode(provider: provider, name: name, parent: root, size: size, modified: modified);

  DirectoryNode dir(String name) => DirectoryNode(provider: provider, name: name, parent: root);

  LinkNode link(String name, {FileType? targetType}) =>
      LinkNode(provider: provider, name: name, parent: root, reference: '/somewhere', targetType: targetType);

  List<String> sorted(List<FsNode> nodes, SortSpec spec) {
    final result = nodes.toList()..sort(comparatorFor(spec));
    return result.map((n) => n.name).toList();
  }

  group('порядок, не зависящий от направления', () {
    test('".." всегда первый', () {
      final directory = DirectoryNode(provider: provider, name: 'sub', parent: root);
      final nodes = <FsNode>[file('zzz.txt'), ParentDirNode(directory), dir('aaa')];

      expect(sorted(nodes, const SortSpec()).first, '..');
      expect(sorted(nodes, const SortSpec(direction: SortDirection.descending)).first, '..');
    });

    test('каталоги выше файлов', () {
      final nodes = <FsNode>[file('aaa.txt'), dir('zzz')];
      expect(sorted(nodes, const SortSpec()), ['zzz', 'aaa.txt']);
      expect(sorted(nodes, const SortSpec(direction: SortDirection.descending)), ['zzz', 'aaa.txt']);
    });

    test('ссылка на каталог считается каталогом', () {
      final nodes = <FsNode>[file('aaa.txt'), link('zlink', targetType: FileType.directory)];
      expect(sorted(nodes, const SortSpec()), ['zlink', 'aaa.txt']);
    });

    test('ссылка на файл остаётся файлом', () {
      final nodes = <FsNode>[link('alink', targetType: FileType.regular), dir('zzz')];
      expect(sorted(nodes, const SortSpec()), ['zzz', 'alink']);
    });

    test('без foldersFirst каталоги и файлы смешиваются', () {
      final nodes = <FsNode>[dir('zzz'), file('aaa.txt')];
      expect(sorted(nodes, const SortSpec(foldersFirst: false)), ['aaa.txt', 'zzz']);
    });
  });

  group('сортировка по колонкам', () {
    test('по имени, с числами как числами', () {
      final nodes = <FsNode>[file('file10.txt'), file('file2.txt'), file('File1.txt')];
      expect(sorted(nodes, const SortSpec()), ['File1.txt', 'file2.txt', 'file10.txt']);
    });

    test('по размеру; неизвестный размер идёт первым', () {
      final nodes = <FsNode>[
        file('big.bin', size: 1000),
        file('small.bin', size: 10),
        file('unknown.bin', size: FsNode.unknownSize),
      ];
      expect(sorted(nodes, const SortSpec(column: FsColumn.size)), ['unknown.bin', 'small.bin', 'big.bin']);
    });

    test('по дате; отсутствующая дата идёт первой', () {
      final nodes = <FsNode>[
        file('new.txt', modified: DateTime(2026, 1, 1)),
        file('old.txt', modified: DateTime(2018, 2, 19)),
        file('none.txt'),
      ];
      expect(sorted(nodes, const SortSpec(column: FsColumn.modified)), ['none.txt', 'old.txt', 'new.txt']);
    });

    test('по расширению', () {
      final nodes = <FsNode>[file('b.xlsx'), file('a.zip'), file('c.doc')];
      expect(sorted(nodes, const SortSpec(column: FsColumn.ext)), ['c.doc', 'b.xlsx', 'a.zip']);
    });

    test('направление переворачивает сравнение по колонке', () {
      final nodes = <FsNode>[file('a.txt'), file('b.txt')];
      expect(sorted(nodes, const SortSpec(direction: SortDirection.descending)), ['b.txt', 'a.txt']);
    });

    test('при равенстве порядок устойчив и задаётся именем', () {
      final nodes = <FsNode>[file('b.txt', size: 10), file('a.txt', size: 10), file('c.txt', size: 10)];
      expect(sorted(nodes, const SortSpec(column: FsColumn.size)), ['a.txt', 'b.txt', 'c.txt']);
    });
  });

  group('naturalCompare', () {
    test('регистр не влияет на порядок', () {
      expect(naturalCompare('Apple', 'apple'), isNot(0));
      expect(naturalCompare('apple', 'Banana'), lessThan(0));
      expect(naturalCompare('Banana', 'apple'), greaterThan(0));
    });

    test('числа сравниваются по значению', () {
      expect(naturalCompare('file2', 'file10'), lessThan(0));
      expect(naturalCompare('v1.10.0', 'v1.9.0'), greaterThan(0));
    });

    test('ведущие нули не меняют значение числа', () {
      expect(naturalCompare('file01', 'file1'), greaterThan(0));
      expect(naturalCompare('file007', 'file8'), lessThan(0));
    });
  });

  group('SortSpec.toggled', () {
    test('та же колонка меняет направление', () {
      const spec = SortSpec();
      final toggled = spec.toggled(FsColumn.name);
      expect(toggled.column, FsColumn.name);
      expect(toggled.direction, SortDirection.descending);
    });

    test('другая колонка сортирует по возрастанию', () {
      const spec = SortSpec(direction: SortDirection.descending);
      final toggled = spec.toggled(FsColumn.size);
      expect(toggled.column, FsColumn.size);
      expect(toggled.direction, SortDirection.ascending);
    });
  });
}
