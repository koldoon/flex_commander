import 'dart:io';

import 'package:flex_commander/model/tree/file_type.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/local/local_tree_provider.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
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
    final node = await provider.resolvePath(root).result;
    return node as DirectoryNode;
  }

  Future<Map<String, FsNode>> listRoot({bool includeHidden = false}) async {
    final dir = await openRoot();
    final nodes = await provider.getDirectoryListing(dir, includeHidden: includeHidden).result;
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
      final nodes = await provider.getDirectoryListing(dir).result;

      expect(nodes.first, isA<ParentDirNode>());
      expect((nodes.first as ParentDirNode).targetDirectory?.pathString, p.dirname(root));
    });

    test('файл получает размер, дату и атрибуты', () async {
      final node = (await listRoot())['notes.txt'] as FileNode;

      expect(node.size, 2048);
      expect(node.modified, isNotNull);
      expect(node.attributes.modeString, startsWith('-'));
      expect(node.extension, 'txt');
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

      final nodes = await provider.getDirectoryListing(dir).result;
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
      final dir = await isolated.resolvePath(root).result as DirectoryNode;
      final nodes = await isolated.getDirectoryListing(dir).result;

      expect(nodes.map((n) => n.name), containsAll(['bin', 'docs', 'notes.txt']));
      expect(nodes.whereType<FileNode>().firstWhere((n) => n.name == 'notes.txt').size, 2048);
    });

    test('отсутствующий каталог даёт FsError', () async {
      final missing = DirectoryNode(provider: provider, name: 'nowhere', parent: await openRoot());

      await expectLater(
        provider.getDirectoryListing(missing).result,
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.notFound)),
      );
    });
  });

  group('разбор пути', () {
    test('строит цепочку узлов до корня', () async {
      final node = await provider.resolvePath(p.join(root, 'docs', 'readme.md')).result;

      expect(node, isA<FileNode>());
      expect(node!.name, 'readme.md');
      expect(node.parentDirectory?.name, 'docs');
      expect(node.path.first, provider.rootDirectory);
      expect(node.pathString, p.join(root, 'docs', 'readme.md'));
    });

    test('несуществующий путь даёт null', () async {
      expect(await provider.resolvePath(p.join(root, 'nope')).result, isNull);
    });

    test('путь через файл никуда не ведёт', () async {
      final node = await provider.resolvePath(p.join(root, 'notes.txt', 'inner')).result;
      expect(node, isNull);
    });

    test('путь через ссылку на каталог разворачивается', () async {
      await File(p.join(root, 'bin', 'tool')).writeAsString('#!/bin/sh');

      final node = await provider.resolvePath(p.join(root, 'bin-link', 'tool')).result;

      expect(node, isA<FileNode>());
      expect(node!.parentDirectory?.name, 'bin');
    });
  });

  group('разрешение ссылки', () {
    test('заполняет target узлом настоящего каталога', () async {
      final link = (await listRoot())['bin-link'] as LinkNode;
      final target = await provider.resolveLink(link).result;

      expect(target, isA<DirectoryNode>());
      expect(link.target, same(target));
      expect(target!.pathString, p.join(root, 'bin'));
    });

    test('битая ссылка не разрешается', () async {
      final link = (await listRoot())['broken-link'] as LinkNode;
      expect(await provider.resolveLink(link).result, isNull);
    });
  });

  test('домашний каталог берётся из окружения', () {
    expect(LocalTreeProvider().homePath, isNotEmpty);
  });
}
