import 'dart:io';

import 'package:flex_commander/model/async/async_operation.dart';
import 'package:flex_commander/model/async/operation_request.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/local/local_tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late String root;
  late String home;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_remove');
    root = await temp.resolveSymbolicLinks();

    // Домашний каталог подменяется временным: корзина живёт в нём, и настоящую
    // корзину пользователя тесты трогать не должны.
    home = p.join(root, 'home');
    await Directory(home).create();
    await Directory(p.join(root, 'docs')).create();
    await File(p.join(root, 'docs', 'readme.md')).writeAsString('hello');
    await File(p.join(root, 'notes.txt')).writeAsString('x');
    await File(p.join(root, 'report.txt')).writeAsString('y');
    await Link(p.join(root, 'link-to-docs')).create(p.join(root, 'docs'));

    provider = LocalTreeProvider(homePath: home, readInIsolate: false);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<Map<String, FsNode>> listRoot() async {
    final dir = (await provider.resolvePath(root).result)! as DirectoryNode;
    final nodes = await provider.getDirectoryListing(dir).result;
    return {for (final node in nodes) node.name: node};
  }

  String trashPath(String name) => p.join(home, '.Trash', name);

  group('удаление в корзину', () {
    test('файл переносится в корзину, а не исчезает', () async {
      final nodes = await listRoot();

      await provider.remove([nodes['notes.txt']!]).result;

      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
      expect(await File(trashPath('notes.txt')).exists(), isTrue);
    });

    test('каталог переносится вместе с содержимым', () async {
      final nodes = await listRoot();

      await provider.remove([nodes['docs']!]).result;

      expect(await Directory(p.join(root, 'docs')).exists(), isFalse);
      expect(await File(p.join(trashPath('docs'), 'readme.md')).exists(), isTrue);
    });

    test('совпадение имён в корзине разводится суффиксом', () async {
      await Directory(p.join(home, '.Trash')).create(recursive: true);
      await File(trashPath('notes.txt')).writeAsString('старый');

      final nodes = await listRoot();
      await provider.remove([nodes['notes.txt']!]).result;

      expect(await File(trashPath('notes.txt')).readAsString(), 'старый');
      expect(await File(trashPath('notes 2.txt')).exists(), isTrue);
    });

    test('удаляется сама ссылка, а не то, куда она ведёт', () async {
      final nodes = await listRoot();

      await provider.remove([nodes['link-to-docs']!]).result;

      expect(await Link(p.join(root, 'link-to-docs')).exists(), isFalse);
      expect(await Directory(p.join(root, 'docs')).exists(), isTrue);
    });
  });

  group('безвозвратное удаление', () {
    test('файл исчезает совсем', () async {
      final nodes = await listRoot();

      await provider.remove([nodes['notes.txt']!], toTrash: false).result;

      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
      expect(await Directory(p.join(home, '.Trash')).exists(), isFalse);
    });

    test('каталог удаляется вместе с содержимым', () async {
      final nodes = await listRoot();

      await provider.remove([nodes['docs']!], toTrash: false).result;

      expect(await Directory(p.join(root, 'docs')).exists(), isFalse);
    });
  });

  group('несколько объектов', () {
    test('удаляются все', () async {
      final nodes = await listRoot();

      await provider.remove([nodes['notes.txt']!, nodes['report.txt']!], toTrash: false).result;

      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
      expect(await File(p.join(root, 'report.txt')).exists(), isFalse);
    });

    test('операция сообщает о ходе работы', () async {
      final nodes = await listRoot();
      final progress = <String>[];

      final operation = provider.remove([nodes['notes.txt']!, nodes['report.txt']!], toTrash: false);
      operation.progress.listen((event) => progress.add(event.message));
      await operation.result;
      await Future<void>.delayed(Duration.zero);

      expect(progress, contains('Deleting notes.txt…'));
      expect(progress.last, 'Done');
    });
  });

  group('ошибки', () {
    Future<FsNode> missingNode() async {
      final nodes = await listRoot();
      final node = nodes['notes.txt']!;
      // Объект исчез уже после того, как панель его показала.
      await File(p.join(root, 'notes.txt')).delete();
      return node;
    }

    test('без слушателя вопросов объект просто пропускается', () async {
      final node = await missingNode();
      final nodes = await listRoot();

      await provider.remove([node, nodes['report.txt']!], toTrash: false).result;

      // Первый пропущен, второй всё равно удалён.
      expect(await File(p.join(root, 'report.txt')).exists(), isFalse);
    });

    test('«пропустить все» больше не спрашивает', () async {
      final nodes = await listRoot();
      // Оба объекта исчезли уже после того, как панель их показала.
      await File(p.join(root, 'notes.txt')).delete();
      await File(p.join(root, 'report.txt')).delete();

      final questions = <String>[];
      final operation = provider.remove([nodes['notes.txt']!, nodes['report.txt']!], toTrash: false);
      operation.requests.listen((request) {
        questions.add(request.message);
        request.respond(OperationOption.skipAll);
      });
      await operation.result;

      expect(questions, hasLength(1));
    });

    test('«отменить» прерывает операцию', () async {
      final missing = await missingNode();
      final nodes = await listRoot();

      final operation = provider.remove([missing, nodes['report.txt']!], toTrash: false);
      operation.requests.listen((request) => request.respond(OperationOption.cancel));

      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
      // До второго объекта дело не дошло.
      expect(await File(p.join(root, 'report.txt')).exists(), isTrue);
    });
  });
}
