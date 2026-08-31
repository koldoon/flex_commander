import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTreeProvider provider;

  setUp(() => provider = InMemoryTreeProvider());

  group('имя узла', () {
    test('скрытым считается имя с точки', () {
      expect(FileNode(provider: provider, name: '.zshrc').hidden, isTrue);
      expect(FileNode(provider: provider, name: 'zshrc').hidden, isFalse);
    });
  });

  group('обход дерева', () {
    late DirectoryNode users;
    late DirectoryNode koldoon;
    late FileNode readme;

    setUp(() {
      users = DirectoryNode(provider: provider, name: 'Users', parent: provider.rootDirectory);
      koldoon = DirectoryNode(provider: provider, name: 'koldoon', parent: users);
      readme = FileNode(provider: provider, name: 'README.md', parent: koldoon);
    });

    test('path идёт от корня к узлу', () {
      expect(readme.path.map((n) => n.name).toList(), ['/', 'Users', 'koldoon', 'README.md']);
    });

    test('pathString собирается провайдером', () {
      expect(readme.pathString, '/Users/koldoon/README.md');
      expect(provider.rootDirectory.pathString, '/');
    });

    test('parentDirectory — ближайший каталог вверх', () {
      expect(readme.parentDirectory, koldoon);
      expect(koldoon.parentDirectory, users);
      expect(provider.rootDirectory.parentDirectory, isNull);
    });
  });

  group('ссылка', () {
    test('info показывает цель', () {
      final link = LinkNode(provider: provider, name: 'latest', reference: '/opt/app-1.2.0');
      expect(link.reference, '/opt/app-1.2.0');
    });

    test('тип цели известен без разрешения ссылки', () {
      provider.add(FakeEntry.directory('/opt'));
      final link = LinkNode(
        provider: provider,
        name: 'opt',
        reference: '/opt',
        targetType: provider.rootDirectory.fileType,
      );
      expect(link.isDirectoryLink, isTrue);
    });
  });

  group('псевдоузел ".."', () {
    test('ведёт в родительский каталог', () {
      final users = DirectoryNode(provider: provider, name: 'Users', parent: provider.rootDirectory);
      final parentNode = ParentDirNode(users);

      expect(parentNode.name, '..');
      expect(parentNode.targetDirectory, provider.rootDirectory);
      expect(parentNode.pathString, '/');
    });

    test('в корне вести некуда', () {
      final parentNode = ParentDirNode(provider.rootDirectory);
      expect(parentNode.targetDirectory, isNull);
    });

    test('для каждого каталога свой экземпляр', () {
      final a = DirectoryNode(provider: provider, name: 'a', parent: provider.rootDirectory);
      final b = DirectoryNode(provider: provider, name: 'b', parent: provider.rootDirectory);
      expect(ParentDirNode(a), isNot(same(ParentDirNode(b))));
    });
  });

  group('размер каталога', () {
    test('по умолчанию неизвестен', () {
      final dir = DirectoryNode(provider: provider, name: 'lib');
      expect(dir.size, FsNode.unknownSize);
    });

    test('выставляется после создания', () {
      final dir = DirectoryNode(provider: provider, name: 'lib');

      // На этом держится показ размера каталога: его считает панель, когда
      // каталог помечают, и пишет прямо в узел.
      dir.size = 300;

      expect(dir.size, 300);
    });
  });
}
