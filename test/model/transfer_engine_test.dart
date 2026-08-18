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

    test('без байтового контракта переносить нечем, и об этом спрашивают', () async {
      final destination = (await remote.resolvePath('/home/bin').result)! as DirectoryNode;
      final operation = engine.copy([await node('/home/notes.txt')], destination);
      final questions = collectQuestions(operation);

      await operation.result;
      await pumpEventQueue();

      // Ни переименования, ни копирования средствами провайдера здесь нет,
      // а байтов ни одна из сторон не отдаёт: остаётся только признаться.
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
      await pumpEventQueue();

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

  group('поток', () {
    late InMemoryContentProvider source;
    late InMemoryContentProvider remote;

    setUp(() {
      source = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/docs/readme.md', content: [1, 2, 3]),
        FakeEntry.file('/home/notes.txt', content: [7, 8, 9, 10]),
      ]);
      remote = InMemoryContentProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/bin')]);
    });

    Future<DirectoryNode> remoteBin() async => (await remote.resolvePath('/home/bin').result)! as DirectoryNode;

    /// Содержимое файла в приёмнике — тем же контрактом, каким его писали.
    Future<List<int>?> remoteContent(String path) async {
      final node = await remote.resolvePath(path).result;
      if (node == null) {
        return null;
      }
      final chunks = await (await remote.openRead(node)).toList();
      return [for (final chunk in chunks) ...chunk];
    }

    test('файл уходит в чужой провайдер вместе с содержимым', () async {
      final file = (await source.resolvePath('/home/notes.txt').result)!;

      await engine.copy([file], await remoteBin()).result;

      expect(await remoteContent('/home/bin/notes.txt'), [7, 8, 9, 10]);
      // Ни переименования, ни копирования средствами провайдера тут быть
      // не могло: провайдеры разные.
      expect(source.renamed, isEmpty);
      expect(source.copied, isEmpty);
    });

    test('приёмник узнаёт размер заранее', () async {
      final file = (await source.resolvePath('/home/notes.txt').result)!;

      await engine.copy([file], await remoteBin()).result;

      // FTP и HTTP просят размер вперёд — движок отдаёт его, когда знает.
      expect(remote.written['/home/bin/notes.txt'], 4);
    });

    test('каталог уезжает целиком, файлы в нём — потоком', () async {
      final docs = (await source.resolvePath('/home/docs').result)!;

      await engine.copy([docs], await remoteBin()).result;

      expect(await remoteContent('/home/bin/docs/readme.md'), [1, 2, 3]);
    });

    test('перенос убирает исходный объект', () async {
      final file = (await source.resolvePath('/home/notes.txt').result)!;

      await engine.move([file], await remoteBin()).result;

      expect(await remoteContent('/home/bin/notes.txt'), [7, 8, 9, 10]);
      expect(await source.resolvePath('/home/notes.txt').result, isNull);
    });

    test('внутри большого файла видно движение', () async {
      source.add(FakeEntry.file('/home/big.bin', content: List.filled(50, 1)));
      final file = (await source.resolvePath('/home/big.bin').result)!;

      final operation = engine.copy([file], await remoteBin());
      final reports = <OperationProgress>[];
      operation.progress.listen(reports.add);
      await operation.result;
      await pumpEventQueue();

      // Объект всё это время один и тот же, а доля растёт: по объектам тут
      // было бы «0 из 1» до самого конца.
      final inside = reports.where((event) => event.bytes > 0 && event.bytes < 50).map((event) => event.bytes);
      expect(inside, [10, 20, 30, 40]);
      expect(reports.last.bytes, 50);
      expect(reports.last.percent, 1);
    });

    test('отмена посреди файла не оставляет обрезанного', () async {
      source.add(FakeEntry.file('/home/big.bin', content: List.filled(50, 1)));
      final file = (await source.resolvePath('/home/big.bin').result)!;

      late final AsyncOperation<void> operation;
      // Первый кусок уже записан — в приёмнике лежит начало файла.
      source.onChunk = () => operation.cancel();
      operation = engine.copy([file], await remoteBin());

      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue();

      expect(await remote.resolvePath('/home/bin/big.bin').result, isNull);
    });

    test('оборвавшаяся передача не оставляет обрезанного файла', () async {
      final broken = _BreakingReadProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/big.bin', content: List.filled(50, 1)),
      ]);
      final file = (await broken.resolvePath('/home/big.bin').result)!;

      final operation = engine.copy([file], await remoteBin());
      final questions = collectQuestions(operation);
      await operation.result;
      await pumpEventQueue();

      // Половина файла под настоящим именем выглядела бы как целый файл.
      expect(questions, hasLength(1));
      expect(await remote.resolvePath('/home/bin/big.bin').result, isNull);
    });

    test('ошибка байтов доводится до общего вида, а работа идёт дальше', () async {
      final broken = _BreakingReadProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/big.bin', content: List.filled(50, 1)),
        FakeEntry.file('/home/small.bin', content: const []),
      ]);
      final first = (await broken.resolvePath('/home/big.bin').result)!;
      final second = (await broken.resolvePath('/home/small.bin').result)!;

      final operation = engine.copy([first, second], await remoteBin());
      final questions = collectQuestions(operation);
      await operation.result;
      await pumpEventQueue();

      // Провайдер бросил из потока что попало — движок перевёл это в FsError,
      // и вопрос задан как по любой другой ошибке.
      expect(questions.single, contains('/home/big.bin'));
      expect(await remoteContent('/home/bin/small.bin'), isEmpty);
    });
  });

  group('просьба прервать', () {
    /// Задание из многих файлов: работу должно быть видно по шагам.
    List<FakeEntry> many() => [
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      for (var i = 0; i < 20; i++) FakeEntry.file('/home/file-$i.txt', size: 1),
    ];

    Future<(AsyncOperation<void>, InMemoryTreeProvider)> startCopy() async {
      final disk = InMemoryTreeProvider(many());
      final sources = [for (var i = 0; i < 20; i++) (await disk.resolvePath('/home/file-$i.txt').result)!];
      final target = (await disk.resolvePath('/home/bin').result)! as DirectoryNode;
      return (engine.copy(sources, target), disk);
    }

    test('спрашивает подтверждение, а не прерывает молча', () async {
      final (operation, _) = await startCopy();
      final questions = <OperationRequest>[];
      operation.requests.listen(questions.add);

      operation.requestCancel();
      await pumpEventQueue();

      expect(questions, hasLength(1));
      expect(questions.single.options, [OperationOption.abort, OperationOption.resume]);
      // Enter прерывает, Esc — отказывается прерывать.
      expect(questions.single.defaultOption, OperationOption.abort);
      expect(questions.single.escapeOption, OperationOption.resume);

      questions.single.respond(OperationOption.abort);
      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
    });

    test('пока ответа нет, работа стоит', () async {
      final (operation, disk) = await startCopy();
      OperationRequest? question;
      operation.requests.listen((request) => question = request);

      operation.requestCancel();
      await pumpEventQueue();
      final done = disk.copied.length;

      // Ждём заведомо дольше, чем занял бы весь остаток задания.
      await pumpEventQueue(times: 100);

      expect(question, isNotNull);
      expect(disk.copied.length, done, reason: 'работа продолжилась, не дождавшись ответа');
      expect(done, lessThan(20), reason: 'задание успело кончиться — проверять нечего');

      question!.respond(OperationOption.resume);
      await operation.result;
    });

    test('«Cancel» возвращает к работе, и она доходит до конца', () async {
      final (operation, disk) = await startCopy();
      operation.requests.listen((request) => request.respond(OperationOption.resume));

      operation.requestCancel();
      await operation.result;

      expect(disk.copied, hasLength(20));
      expect(operation.status, OperationStatus.complete);
    });

    test('«Abort» прекращает работу на том, что успели', () async {
      final (operation, disk) = await startCopy();
      operation.requests.listen((request) => request.respond(OperationOption.abort));

      operation.requestCancel();
      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));

      // Сделанное остаётся сделанным, остальное не начиналось.
      expect(disk.copied.length, lessThan(20));
    });

    test('спросить некого — прерывается, как и просили', () async {
      final (operation, _) = await startCopy();

      // Ни окна, ни слушателя: работу запустил сценарий.
      operation.requestCancel();

      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
    });

    test('удаление спрашивает так же', () async {
      final disk = InMemoryTreeProvider(many())..hasTrash = false;
      final sources = [for (var i = 0; i < 20; i++) (await disk.resolvePath('/home/file-$i.txt').result)!];
      final operation = engine.remove(sources, toTrash: false);
      final questions = <OperationRequest>[];
      operation.requests.listen(questions.add);

      operation.requestCancel();
      await pumpEventQueue();

      expect(questions.single.message, 'Abort the operation?');
      questions.single.respond(OperationOption.abort);
      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
    });

    test('прерывание без спроса по-прежнему возможно', () async {
      final (operation, _) = await startCopy();
      final questions = <OperationRequest>[];
      operation.requests.listen(questions.add);
      // Ожидание ставится до отмены: `cancel` завершает операцию ошибкой сразу,
      // и прочитать её должно быть кому уже в этот момент.
      final canceled = expectLater(operation.result, throwsA(isA<OperationCanceled>()));

      // Закрытие приложения не спрашивает: спрашивать уже некого.
      operation.cancel();
      await pumpEventQueue();

      expect(questions, isEmpty);
      await canceled;
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
      await pumpEventQueue();

      // Каталог с тремя вложенными объектами и файл — пять объектов.
      final counted = reports.where((event) => event.totalIsFinal);
      expect(counted.last.total, 5);
      expect(reports.last.processed, reports.last.total);
      expect(reports.last.percent, 1);
    });
  });
}

/// Провайдер, у которого чтение обрывается на первом же куске: так ведёт себя
/// оборвавшаяся сеть.
class _BreakingReadProvider extends InMemoryContentProvider {
  _BreakingReadProvider([super.entries]);

  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final content = await super.openRead(node, offset: offset);
    return () async* {
      await for (final chunk in content) {
        // Первый кусок доходит — значит в приёмнике уже что-то лежит.
        yield chunk;
        throw const _SocketFailure();
      }
    }();
  }
}

/// Ошибка не из мира дерева: движок обязан довести её до FsError сам.
class _SocketFailure implements Exception {
  const _SocketFailure();
}

/// Источник только для чтения: примитивов изменения у него нет — так выглядит
/// архив, открытый на просмотр.
class _ReadOnlyProvider implements TreeProvider {
  @override
  String get scheme => 'ro';

  @override
  String pathOf(FsNode node) => node.name;

  // Остальное этому тесту не нужно: движок отказывается работать раньше, чем
  // спросит у провайдера хоть что-то.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
