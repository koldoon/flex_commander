import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Работу делает движок, провайдер даёт ему примитивы: своего состояния
/// у движка нет, поэтому он один на все тесты файла.
const editor = TreeTransferEngine();

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
    final dir = (await provider.resolvePath().run(root))! as DirectoryNode;
    final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
    return {for (final node in nodes) node.name: node};
  }

  String trashPath(String name) => p.join(home, '.Trash', name);

  group('удаление в корзину', () {
    test('файл переносится в корзину, а не исчезает', () async {
      final nodes = await listRoot();

      await editor.remove().run(RemoveParams([nodes['notes.txt']!]));

      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
      expect(await File(trashPath('notes.txt')).exists(), isTrue);
    });

    test('каталог переносится вместе с содержимым', () async {
      final nodes = await listRoot();

      await editor.remove().run(RemoveParams([nodes['docs']!]));

      expect(await Directory(p.join(root, 'docs')).exists(), isFalse);
      expect(await File(p.join(trashPath('docs'), 'readme.md')).exists(), isTrue);
    });

    test('совпадение имён в корзине разводится суффиксом', () async {
      await Directory(p.join(home, '.Trash')).create(recursive: true);
      await File(trashPath('notes.txt')).writeAsString('старый');

      final nodes = await listRoot();
      await editor.remove().run(RemoveParams([nodes['notes.txt']!]));

      expect(await File(trashPath('notes.txt')).readAsString(), 'старый');
      expect(await File(trashPath('notes 2.txt')).exists(), isTrue);
    });

    test('удаляется сама ссылка, а не то, куда она ведёт', () async {
      final nodes = await listRoot();

      await editor.remove().run(RemoveParams([nodes['link-to-docs']!]));

      expect(await Link(p.join(root, 'link-to-docs')).exists(), isFalse);
      expect(await Directory(p.join(root, 'docs')).exists(), isTrue);
    });
  });

  group('безвозвратное удаление', () {
    test('файл исчезает совсем', () async {
      final nodes = await listRoot();

      await editor.remove().run(RemoveParams([nodes['notes.txt']!], toTrash: false));

      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
      expect(await Directory(p.join(home, '.Trash')).exists(), isFalse);
    });

    test('каталог удаляется вместе с содержимым', () async {
      final nodes = await listRoot();

      await editor.remove().run(RemoveParams([nodes['docs']!], toTrash: false));

      expect(await Directory(p.join(root, 'docs')).exists(), isFalse);
    });
  });

  group('несколько объектов', () {
    test('удаляются все', () async {
      final nodes = await listRoot();

      await editor.remove().run(RemoveParams([nodes['notes.txt']!, nodes['report.txt']!], toTrash: false));

      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
      expect(await File(p.join(root, 'report.txt')).exists(), isFalse);
    });

    test('операция сообщает о ходе работы', () async {
      final nodes = await listRoot();

      final operation = editor.remove();
      final log = ProgressLog.of(operation);
      operation.start(RemoveParams([nodes['notes.txt']!, nodes['report.txt']!], toTrash: false));
      await operation.result;
      await pumpEventQueue();
      await Future<void>.delayed(Duration.zero);

      expect(log.reports.map((report) => report.message), contains('notes.txt'));
      expect(log.last.message, 'Done');
    });

    test('счётчик проходит по всему содержимому каталога', () async {
      final nodes = await listRoot();
      final operation = editor.remove();
      final reports = ProgressLog.of(operation).reports;

      operation.start(RemoveParams([nodes['docs']!], toTrash: false));
      await operation.result;
      await pumpEventQueue();
      await Future<void>.delayed(Duration.zero);

      // Каталог и файл внутри: удаление большого дерева не стоит на нуле.
      expect(reports.map((event) => event.itemsTransferred).toSet().length, greaterThan(1));
      // Источник задания не меняется: удаляют каталог, а не то, что внутри.
      final named = reports.map((event) => event.message).where((message) => message.isNotEmpty && message != 'Done');
      expect(named, everyElement('docs'));
      expect(reports.last.percent, 1);
      expect(reports.last.itemsTransferred, 2);
    });

    test('удаление в корзину доводит счётчик до конца одним действием', () async {
      final nodes = await listRoot();
      final operation = editor.remove();
      final reports = ProgressLog.of(operation).reports;

      operation.start(RemoveParams([nodes['docs']!]));
      await operation.result;
      await pumpEventQueue();
      await Future<void>.delayed(Duration.zero);

      // Корзина — это переименование: поштучно объекты не проходили.
      expect(reports.last.percent, 1);
      expect(reports.last.itemsTransferred, reports.last.itemsTotal);
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

      await editor.remove().run(RemoveParams([node, nodes['report.txt']!], toTrash: false));

      // Первый пропущен, второй всё равно удалён.
      expect(await File(p.join(root, 'report.txt')).exists(), isFalse);
    });

    test('«пропустить все» больше не спрашивает', () async {
      final nodes = await listRoot();
      // Оба объекта исчезли уже после того, как панель их показала.
      await File(p.join(root, 'notes.txt')).delete();
      await File(p.join(root, 'report.txt')).delete();

      final questions = <String>[];
      final operation = editor.remove();
      operation.requests.listen((request) {
        questions.add(request.message);
        request.respond(OperationRequestOption.skipAll);
      });

      operation.start(RemoveParams([nodes['notes.txt']!, nodes['report.txt']!], toTrash: false));
      await operation.result;
      await pumpEventQueue();

      expect(questions, hasLength(1));
    });

    test('«отменить» прерывает операцию', () async {
      final missing = await missingNode();
      final nodes = await listRoot();

      final operation = editor.remove();
      operation.requests.listen((request) => request.respond(OperationRequestOption.cancel));

      operation.start(RemoveParams([missing, nodes['report.txt']!], toTrash: false));
      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
      // До второго объекта дело не дошло.
      expect(await File(p.join(root, 'report.txt')).exists(), isTrue);
    });
  });
}
