import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_local_fs/backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Работу делает движок, провайдер даёт ему примитивы: своего состояния
/// у движка нет, поэтому он один на все тесты файла.
const editor = TreeTransferEngine();

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

  Future<DirectoryNode> openRoot() async => (await provider.resolvePath().run(root))! as DirectoryNode;

  test('создаёт каталог и возвращает его узел', () async {
    final parent = await openRoot();
    final created = await editor.makeDirectory().run(MakeDirectoryParams(parent, 'docs'));

    expect(await Directory(p.join(root, 'docs')).exists(), isTrue);
    expect(created.name, 'docs');
    expect(created.parent, same(parent));
    expect(created.pathString, p.join(root, 'docs'));
  });

  test('новый каталог сразу виден в панели после перечитывания', () async {
    final parent = await openRoot();
    await editor.makeDirectory().run(MakeDirectoryParams(parent, 'docs'));

    final nodes = await provider.getDirectoryListing().run(ListingParams(parent));
    expect(nodes.map((n) => n.name), contains('docs'));
  });

  test('внутри ссылки каталог создаётся по настоящему пути', () async {
    final link = (await provider.resolvePath().run(p.join(root, 'bin-link')))! as LinkNode;
    final target = (await provider.resolveLink().run(link))! as DirectoryNode;

    final created = await editor.makeDirectory().run(MakeDirectoryParams(target, 'tools'));

    // Файл лежит в настоящем каталоге...
    expect(await Directory(p.join(root, 'bin', 'tools')).exists(), isTrue);
    // ...а пользователь видит путь, по которому пришёл.
    expect(created.pathString, p.join(root, 'bin-link', 'tools'));
  });

  test('существующее имя даёт ошибку', () async {
    final parent = await openRoot();

    await expectLater(
      editor.makeDirectory().run(MakeDirectoryParams(parent, 'bin')),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
    );
  });

  test('занятое файлом имя даёт ошибку', () async {
    await File(p.join(root, 'notes.txt')).writeAsString('x');
    final parent = await openRoot();

    await expectLater(
      editor.makeDirectory().run(MakeDirectoryParams(parent, 'notes.txt')),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
    );
  });

  test('недопустимое имя даёт ошибку', () async {
    final parent = await openRoot();

    for (final name in ['', '.', '..', 'a/b']) {
      await expectLater(
        editor.makeDirectory().run(MakeDirectoryParams(parent, name)),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.invalidName)),
        reason: 'имя «$name» должно быть отклонено',
      );
    }
  });

  test('провайдер локальной ФС даёт примитивы, а операции выполняет движок', () {
    expect(provider, isA<NodeEditor>());
    // Операцию целиком провайдер не выполняет: обход, конфликты и прогресс —
    // не его дело.
    expect(provider, isNot(isA<TreeEditor>()));
    expect(editor, isA<TreeEditor>());
  });
}
