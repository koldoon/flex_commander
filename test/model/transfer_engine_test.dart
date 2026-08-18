import 'package:flex_commander/model/async/async_operation.dart';
import 'package:flex_commander/model/async/operation_request.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/transfer/transfer_engine.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake/in_memory_tree_provider.dart';

/// Движок переноса: то, что раньше писал каждый провайдер сам.
///
/// Проверяется здесь не результат на диске (это делают `transfer_test` и
/// `remove_test` на настоящей ФС), а решения самого движка: какой стратегией он
/// пошёл, что делает с двумя разными провайдерами и как обходит дерево.
void main() {
  const engine = TreeTransferEngine();

  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/home/docs/nested'),
      FakeEntry.file('/home/docs/readme.md', size: 5),
      FakeEntry.file('/home/docs/nested/deep.txt', size: 4),
      FakeEntry.file('/home/notes.txt', size: 10),
    ]);
  });

  Future<FsNode> node(String path) async => (await provider.resolvePath(path).result)!;

  Future<DirectoryNode> directory(String path) async => (await node(path)) as DirectoryNode;

  /// Собирает вопросы, отвечая «пропустить».
  List<String> collectQuestions(AsyncOperation<void> operation) {
    final messages = <String>[];
    operation.requests.listen((request) {
      messages.add(request.message);
      request.respond(OperationOption.skip);
    });
    return messages;
  }

  group('стратегии', () {
    test('перенос в пределах провайдера идёт переименованием', () async {
      await engine.move([await node('/home/notes.txt')], await directory('/home/bin')).result;

      expect(provider.renamed, ['/home/notes.txt']);
      // Переименование переносит объект целиком: копировать нечего.
      expect(provider.copied, isEmpty);
      expect(await provider.resolvePath('/home/bin/notes.txt').result, isNotNull);
      expect(await provider.resolvePath('/home/notes.txt').result, isNull);
    });

    test('без переименования объект копируется и удаляется', () async {
      // Так ведёт себя перенос между дисками: `EXDEV` — это false из примитива.
      provider.renames = false;

      await engine.move([await node('/home/notes.txt')], await directory('/home/bin')).result;

      expect(provider.renamed, isEmpty);
      expect(provider.copied, ['/home/notes.txt']);
      expect(await provider.resolvePath('/home/bin/notes.txt').result, isNotNull);
      expect(await provider.resolvePath('/home/notes.txt').result, isNull);
    });

    test('копирование переименованием не пользуется', () async {
      await engine.copy([await node('/home/notes.txt')], await directory('/home/bin')).result;

      expect(provider.renamed, isEmpty);
      expect(provider.copied, ['/home/notes.txt']);
      expect(await provider.resolvePath('/home/notes.txt').result, isNotNull);
    });

    test('каталог движок создаёт и обходит сам, а не отдаёт провайдеру', () async {
      await engine.copy([await node('/home/docs')], await directory('/home/bin')).result;

      // Провайдер копировал только файлы: каталоги создавал движок, поштучно —
      // иначе о ходе работы внутри дерева было бы нечего сказать.
      expect(provider.copied, ['/home/docs/nested/deep.txt', '/home/docs/readme.md']);
      expect(await provider.resolvePath('/home/bin/docs/nested/deep.txt').result, isNotNull);
      expect(await provider.resolvePath('/home/bin/docs/readme.md').result, isNotNull);
    });

    test('удаление в корзину — одно действие, мимо корзины — обход', () async {
      await engine.remove([await node('/home/docs')]).result;
      expect(provider.trashed, ['/home/docs']);
      expect(provider.deleted, isEmpty);

      final other = InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/docs/readme.md', size: 5),
      ])..hasTrash = false;
      final target = (await other.resolvePath('/home/docs').result)! as DirectoryNode;

      await engine.remove([target]).result;

      // Корзины нет — движок удаляет поддерево снизу вверх, показывая каждый шаг.
      expect(other.trashed, isEmpty);
      expect(other.deleted, ['/home/docs/readme.md', '/home/docs']);
    });
  });

  group('два провайдера', () {
    late InMemoryTreeProvider remote;

    setUp(() {
      remote = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/bin')]);
    });

    test('перенос между провайдерами пока невозможен, и об этом спрашивают', () async {
      final destination = (await remote.resolvePath('/home/bin').result)! as DirectoryNode;
      final operation = engine.copy([await node('/home/notes.txt')], destination);
      final questions = collectQuestions(operation);

      await operation.result;

      // Ни переименования, ни копирования средствами провайдера здесь нет, а
      // потока и моста ещё нет вовсе (5.2) — движок признаётся честно.
      expect(questions.single, FsError('/home/notes.txt', FsErrorKind.notSupported).message);
      expect(await remote.resolvePath('/home/bin/notes.txt').result, isNull);
    });

    test('невозможный объект не прекращает работу над остальными', () async {
      remote.add(FakeEntry.file('/home/local.txt', size: 1));
      final destination = (await remote.resolvePath('/home/bin').result)! as DirectoryNode;
      final foreign = await node('/home/notes.txt');
      final mine = (await remote.resolvePath('/home/local.txt').result)!;

      final operation = engine.copy([foreign, mine], destination);
      final questions = collectQuestions(operation);
      await operation.result;

      // Один источник чужой, другой свой: вопрос задан по первому, второй
      // скопирован.
      expect(questions, hasLength(1));
      expect(await remote.resolvePath('/home/bin/notes.txt').result, isNull);
      expect(await remote.resolvePath('/home/bin/local.txt').result, isNotNull);
    });

    test('приёмник только для чтения — работа не начинается', () async {
      final readOnly = _ReadOnlyProvider();
      final destination = DirectoryNode(provider: readOnly, name: 'archive.zip');

      final operation = engine.copy([await node('/home/notes.txt')], destination);

      await expectLater(operation.result, throwsA(isA<FsError>()));
      expect(operation.status, OperationStatus.error);
    });
  });

  group('обход', () {
    test('не подменяет содержимое каталога, открытого в панели', () async {
      final docs = await directory('/home/docs');
      final shown = await provider.getDirectoryListing(docs).result;

      await engine.copy([docs], await directory('/home/bin')).result;

      // Обход движка читает то же самое, но мимо узла: иначе в панели вместо
      // её списка (с «..» и без скрытых) оказался бы список для копирования.
      expect(docs.nodes, orderedEquals(shown));
      expect(docs.nodes.first, isA<ParentDirNode>());
    });

    test('счётчики доходят до конца и на переименовании, и на обходе', () async {
      final operation = engine.copy([
        await node('/home/docs'),
        await node('/home/notes.txt'),
      ], await directory('/home/bin'));
      final reports = <OperationProgress>[];
      operation.progress.listen(reports.add);

      await operation.result;

      // Каталог с тремя вложенными объектами и файл — пять объектов.
      final counted = reports.where((event) => event.totalIsFinal);
      expect(counted.last.total, 5);
      expect(reports.last.processed, reports.last.total);
      expect(reports.last.percent, 1);
    });
  });
}

/// Источник только для чтения: примитивов изменения у него нет — так выглядит
/// архив, открытый на просмотр.
class _ReadOnlyProvider implements TreeProvider {
  @override
  String pathOf(FsNode node) => node.name;

  // Остальное этому тесту не нужно: движок отказывается работать раньше, чем
  // спросит у провайдера хоть что-то.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
