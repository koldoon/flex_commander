import 'dart:io';

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
    temp = await Directory.systemTemp.createTemp('flex_commander_mkdir');
    root = await temp.resolveSymbolicLinks();
    await Directory(p.join(root, 'bin')).create();
    await Link(p.join(root, 'bin-link')).create(p.join(root, 'bin'));
    provider = LocalTreeProvider(homePath: root, readInIsolate: false);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<DirectoryNode> openRoot() async => (await provider.resolvePath(root).result)! as DirectoryNode;

  test('создаёт каталог и возвращает его узел', () async {
    final parent = await openRoot();
    final created = await provider.makeDirectory(parent, 'docs').result;

    expect(await Directory(p.join(root, 'docs')).exists(), isTrue);
    expect(created.name, 'docs');
    expect(created.parent, same(parent));
    expect(created.pathString, p.join(root, 'docs'));
  });

  test('новый каталог сразу виден в панели после перечитывания', () async {
    final parent = await openRoot();
    await provider.makeDirectory(parent, 'docs').result;

    final nodes = await provider.getDirectoryListing(parent).result;
    expect(nodes.map((n) => n.name), contains('docs'));
  });

  test('внутри ссылки каталог создаётся по настоящему пути', () async {
    final link = (await provider.resolvePath(p.join(root, 'bin-link')).result)! as LinkNode;
    final target = (await provider.resolveLink(link).result)! as DirectoryNode;

    final created = await provider.makeDirectory(target, 'tools').result;

    // Файл лежит в настоящем каталоге...
    expect(await Directory(p.join(root, 'bin', 'tools')).exists(), isTrue);
    // ...а пользователь видит путь, по которому пришёл.
    expect(created.pathString, p.join(root, 'bin-link', 'tools'));
  });

  test('существующее имя даёт ошибку', () async {
    final parent = await openRoot();

    await expectLater(
      provider.makeDirectory(parent, 'bin').result,
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
    );
  });

  test('занятое файлом имя даёт ошибку', () async {
    await File(p.join(root, 'notes.txt')).writeAsString('x');
    final parent = await openRoot();

    await expectLater(
      provider.makeDirectory(parent, 'notes.txt').result,
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
    );
  });

  test('недопустимое имя даёт ошибку', () async {
    final parent = await openRoot();

    for (final name in ['', '.', '..', 'a/b']) {
      await expectLater(
        provider.makeDirectory(parent, name).result,
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.invalidName)),
        reason: 'имя «$name» должно быть отклонено',
      );
    }
  });

  test('провайдер локальной ФС умеет изменять дерево', () {
    expect(provider, isA<TreeEditor>());
  });
}
