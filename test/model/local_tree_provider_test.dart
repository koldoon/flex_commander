import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_local_fs/backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late String root;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_test');
    // На macOS системный временный каталог лежит за символической ссылкой
    // (/var -> /private/var), поэтому сравниваем пути в разрешённом виде.
    root = await temp.resolveSymbolicLinks();

    await Directory(p.join(root, 'bin')).create();
    await Directory(p.join(root, 'docs')).create();
    await File(p.join(root, 'docs', 'readme.md')).writeAsString('hello');
    await File(p.join(root, 'notes.txt')).writeAsString('x' * 2048);
    await File(p.join(root, '.hidden')).writeAsString('secret');
    await Link(p.join(root, 'bin-link')).create(p.join(root, 'bin'));
    await Link(p.join(root, 'broken-link')).create(p.join(root, 'nowhere'));

    provider = LocalTreeProvider(homePath: root, readInIsolate: false);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<DirectoryNode> openRoot() async {
    final node = await provider.resolvePath().run(root);
    return node as DirectoryNode;
  }

  Future<Map<String, FsNode>> listRoot({bool includeHidden = false}) async {
    final dir = await openRoot();
    final nodes = await provider.getDirectoryListing().run(ListingParams(dir, includeHidden: includeHidden));
    return {for (final node in nodes) node.name: node};
  }

  group('чтение каталога', () {
    test('возвращает файлы, каталоги и ссылки', () async {
      final nodes = await listRoot();

      expect(nodes.keys, containsAll(['bin', 'docs', 'notes.txt', 'bin-link']));
      expect(nodes['bin'], isA<DirectoryNode>());
      expect(nodes['notes.txt'], isA<FileNode>());
      expect(nodes['bin-link'], isA<LinkNode>());
    });

    test('скрытые объекты по умолчанию не показываются', () async {
      expect((await listRoot()).containsKey('.hidden'), isFalse);
      expect((await listRoot(includeHidden: true)).containsKey('.hidden'), isTrue);
    });

    test('первым идёт псевдоузел ".."', () async {
      final dir = await openRoot();
      final nodes = await provider.getDirectoryListing().run(ListingParams(dir));

      expect(nodes.first, isA<ParentDirNode>());
      expect((nodes.first as ParentDirNode).targetDirectory?.pathString, p.dirname(root));
    });

    test('файл получает размер, дату и атрибуты', () async {
      final node = (await listRoot())['notes.txt'] as FileNode;

      expect(node.size, 2048);
      expect(node.modified, isNotNull);
      expect(node.attributes.modeString, startsWith('-'));
      expect(extensionOf(node.name), 'txt');
      expect(node.broken, isFalse);
    });

    test('у каталога размер неизвестен', () async {
      final node = (await listRoot())['bin'] as DirectoryNode;

      expect(node.size, FsNode.unknownSize);
      expect(node.fileType, FileType.directory);
    });

    test('ссылка знает свою цель и её тип', () async {
      final node = (await listRoot())['bin-link'] as LinkNode;

      expect(node.reference, p.join(root, 'bin'));
      expect(node.targetType, FileType.directory);
      expect(node.isDirectoryLink, isTrue);
      expect(node.fileType, FileType.symbolicLink);
    });

    test('битая ссылка помечается, но не ломает чтение', () async {
      final node = (await listRoot())['broken-link'] as LinkNode;

      expect(node.broken, isTrue);
      expect(node.targetType, isNull);
      expect(node.isDirectoryLink, isFalse);
    });

    test('результат сохраняется в самом каталоге', () async {
      final dir = await openRoot();
      expect(dir.nodes, isEmpty);

      final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
      expect(dir.nodes, orderedEquals(nodes));
    });

    test('атрибуты начинаются с символа типа', () async {
      final nodes = await listRoot();

      expect((nodes['notes.txt']! as FileNode).attributes.modeString, startsWith('-'));
      expect((nodes['bin']! as FileNode).attributes.modeString, startsWith('d'));
      expect((nodes['bin-link']! as FileNode).attributes.modeString, startsWith('l'));
    });

    test('чтение в изоляте даёт тот же результат', () async {
      final isolated = LocalTreeProvider(homePath: root);
      final dir = await isolated.resolvePath().run(root) as DirectoryNode;
      final nodes = await isolated.getDirectoryListing().run(ListingParams(dir));

      expect(nodes.map((n) => n.name), containsAll(['bin', 'docs', 'notes.txt']));
      expect(nodes.whereType<FileNode>().firstWhere((n) => n.name == 'notes.txt').size, 2048);
    });

    test('отсутствующий каталог даёт FsError', () async {
      final missing = DirectoryNode(provider: provider, name: 'nowhere', parent: await openRoot());

      await expectLater(
        provider.getDirectoryListing().run(ListingParams(missing)),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.notFound)),
      );
    });
  });

  group('разбор пути', () {
    test('строит цепочку узлов до корня', () async {
      final node = await provider.resolvePath().run(p.join(root, 'docs', 'readme.md'));

      expect(node, isA<FileNode>());
      expect(node!.name, 'readme.md');
      expect(node.parentDirectory?.name, 'docs');
      expect(node.path.first, provider.rootDirectory);
      expect(node.pathString, p.join(root, 'docs', 'readme.md'));
    });

    test('несуществующий путь даёт null', () async {
      expect(await provider.resolvePath().run(p.join(root, 'nope')), isNull);
    });

    test('путь через файл никуда не ведёт', () async {
      final node = await provider.resolvePath().run(p.join(root, 'notes.txt', 'inner'));
      expect(node, isNull);
    });

    test('путь через ссылку на каталог разворачивается', () async {
      await File(p.join(root, 'bin', 'tool')).writeAsString('#!/bin/sh');

      final node = await provider.resolvePath().run(p.join(root, 'bin-link', 'tool'));

      expect(node, isA<FileNode>());
      expect(node!.pathString, p.join(root, 'bin-link', 'tool'));
      expect(provider.physicalPathOf(node), p.join(root, 'bin', 'tool'));
    });
  });

  group('разрешение ссылки', () {
    test('цель становится дочерним узлом ссылки', () async {
      final link = (await listRoot())['bin-link'] as LinkNode;
      final target = await provider.resolveLink().run(link);

      expect(target, isA<DirectoryNode>());
      expect(link.target, same(target));
      expect(target!.parent, same(link));
    });

    test('видимый путь идёт через ссылку, настоящий — через цель', () async {
      final link = (await listRoot())['bin-link'] as LinkNode;
      final target = (await provider.resolveLink().run(link))!;

      // Пользователь зашёл в bin-link — его он и должен видеть в заголовке.
      expect(target.pathString, p.join(root, 'bin-link'));
      // А читать надо настоящий каталог.
      expect(provider.physicalPathOf(target), p.join(root, 'bin'));
    });

    test('наверх ведёт каталог со ссылкой, а не с её целью', () async {
      final link = (await listRoot())['bin-link'] as LinkNode;
      final target = (await provider.resolveLink().run(link))! as DirectoryNode;

      // Родительский каталог цели — тот, где лежит ссылка.
      expect(target.parentDirectory?.pathString, root);
    });

    test('содержимое читается из настоящего каталога', () async {
      await File(p.join(root, 'bin', 'tool')).writeAsString('#!/bin/sh');

      final link = (await listRoot())['bin-link'] as LinkNode;
      final target = (await provider.resolveLink().run(link))! as DirectoryNode;
      final nodes = await provider.getDirectoryListing().run(ListingParams(target));

      expect(nodes.map((n) => n.name), containsAll(['..', 'tool']));
      // И путь файла внутри ссылки тоже остаётся видимым.
      expect(nodes.firstWhere((n) => n.name == 'tool').pathString, p.join(root, 'bin-link', 'tool'));
    });

    test('цепочка ссылок разворачивается до настоящего узла', () async {
      await Link(p.join(root, 'bin-link-2')).create(p.join(root, 'bin-link'));

      final link = (await listRoot())['bin-link-2'] as LinkNode;
      final target = await provider.resolveLink().run(link);

      expect(target, isA<DirectoryNode>());
      expect(provider.physicalPathOf(target!), p.join(root, 'bin'));
      expect(target.pathString, p.join(root, 'bin-link-2'));
    });

    test('закольцованная ссылка не разрешается', () async {
      await Link(p.join(root, 'loop')).create(p.join(root, 'loop'));

      final link = (await listRoot())['loop'] as LinkNode;
      expect(await provider.resolveLink().run(link), isNull);
    });

    test('битая ссылка не разрешается', () async {
      final link = (await listRoot())['broken-link'] as LinkNode;
      expect(await provider.resolveLink().run(link), isNull);
    });
  });

  test('домашний каталог берётся из окружения', () {
    expect(LocalTreeProvider().homePath, isNotEmpty);
  });
}
