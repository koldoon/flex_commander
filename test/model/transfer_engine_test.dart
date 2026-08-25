import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<FsNode> node(String path) async => (await provider.resolvePath().run(path))!;

  Future<DirectoryNode> directory(String path) async => (await node(path)) as DirectoryNode;

  group('перезапись каталога', () {
    /// Приёмник, который поддерева одним действием удалять не умеет, — так
    /// ведёт себя SFTP: там каждый объект это отдельный обмен с сервером.
    late _SlowDeleteProvider remote;

    setUp(() {
      remote = _SlowDeleteProvider([
        FakeEntry.directory('/box'),
        // Прошлое копирование не доехало: каталог есть, а внутри половина.
        FakeEntry.directory('/box/docs'),
        FakeEntry.file('/box/docs/readme.md', size: 5),
      ]);
    });

    test('уборка приёмника не идёт молча', () async {
      final target = (await remote.resolvePath().run('/box'))! as DirectoryNode;
      final operation = engine.copy();
      final log = ProgressLog.of(operation);
      operation.requests.listen((request) => request.respond(OperationRequestOption.overwriteAll));

      operation.start(TransferParams([await node('/home/docs')], target));
      await operation.result;
      await pumpEventQueue();

      // Между ответом и первым скопированным объектом окно не должно замирать:
      // по сети уборка идёт минутами, и «ничего не происходит» — худшее из
      // того, что можно показать.
      expect(
        log.reports.map((report) => report.message),
        contains(predicate<String>((message) => message.contains('readme.md') && message.startsWith('Removing'))),
        reason: 'об уборке приёмника надо рассказывать так же, как о переносе',
      );
    });

    test('счётчики задания уборкой не двигаются', () async {
      final target = (await remote.resolvePath().run('/box'))! as DirectoryNode;
      final operation = engine.copy();
      final log = ProgressLog.of(operation);
      operation.requests.listen((request) => request.respond(OperationRequestOption.overwriteAll));

      operation.start(TransferParams([await node('/home/docs')], target));
      await operation.result;
      await pumpEventQueue();

      // Убранные объекты — не наши: в задании их не было, и в счёт они не идут.
      final duringChore = log.reports.where((report) => report.message.startsWith('Removing'));
      expect(duringChore, isNotEmpty);
      expect(duringChore.map((report) => report.itemsTransferred).toSet(), {0});
    });
  });

  group('плечи работы', () {
    late _BatchingProvider archive;

    setUp(() {
      archive = _BatchingProvider([FakeEntry.directory('/box')]);
    });

    test('у приёмника, применяющего накопленное разом, работа двуплечая', () async {
      final target = (await archive.resolvePath().run('/box'))! as DirectoryNode;
      final operation = engine.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([await node('/home/notes.txt')], target));
      await operation.result;
      await Future<void>.delayed(Duration.zero);

      // Первое плечо — сама запись, второе — то, чем занят приёмник; и назвал
      // его он сам.
      expect(reports.map((report) => report.stageName), contains('copying'));
      expect(reports.map((report) => report.stageName), contains('repacking archive'));
      expect(archive.calls, ['begin', 'end']);
    });

    test('о втором плече рассказано до того, как оно началось', () async {
      final target = (await archive.resolvePath().run('/box'))! as DirectoryNode;
      final operation = engine.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([await node('/home/notes.txt')], target));
      await operation.result;
      await Future<void>.delayed(Duration.zero);

      final repacking = reports.lastWhere((report) => report.stageName == 'repacking archive');

      // Сколько в пересборке работы, не знает никто: доли нет, но видно, что
      // работа идёт — иначе окно замерло бы на «готово».
      expect(repacking.hasStages, isTrue);
      expect(repacking.percent, isNull);
    });

    test('обычному приёмнику плечи не заводятся', () async {
      final operation = engine.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([await node('/home/notes.txt')], await directory('/home/bin')));
      await operation.result;
      await Future<void>.delayed(Duration.zero);

      expect(reports.every((report) => !report.hasStages), isTrue);
    });
  });

  /// Собирает вопросы, отвечая «пропустить».
  List<String> collectQuestions(Operation<Object?, void> operation) {
    final messages = <String>[];
    operation.requests.listen((request) {
      messages.add(request.message);
      request.respond(OperationRequestOption.skip);
    });
    return messages;
  }

  group('символические ссылки', () {
    late InMemoryContentProvider disk;

    setUp(() {
      // С содержимым: перенос на чужой провайдер идёт байтами, и источнику
      // должно быть что отдать.
      disk = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/box'),
        FakeEntry.directory('/home/src'),
        FakeEntry.directory('/home/src/real'),
        FakeEntry.file('/home/src/real/inside.txt', size: 7),
        // Ссылка на каталог: узел у неё не `DirectoryNode`, и поток по ней не
        // открыть — на этом падала упаковка каталога с `.framework` внутри.
        FakeEntry.link('/home/src/link', '/home/src/real'),
      ]);
    });

    Future<FsNode> at(String path) async => (await disk.resolvePath().run(path))!;

    Future<DirectoryNode> dir(String path) async => (await at(path)) as DirectoryNode;

    test('ссылка на каталог не роняет работу', () async {
      final operation = engine.copy();
      collectQuestions(operation);

      operation.start(TransferParams([await dir('/home/src')], await dir('/home/box')));
      await operation.result;

      expect(await disk.resolvePath().run('/home/box/src/link'), isNotNull);
    });

    test('не следуем — ссылка уходит ссылкой, а не содержимым', () async {
      final operation = engine.copy();
      collectQuestions(operation);
      operation.start(TransferParams([await dir('/home/src')], await dir('/home/box')));
      await operation.result;

      final copied = await disk.resolvePath().run('/home/box/src/link');

      expect(copied, isA<LinkNode>());
      // Указывает туда же, куда и оригинал: содержимое цели не поехало копией
      // — это разные вещи и по размеру, и по смыслу. Пройти по ссылке из копии
      // по-прежнему можно, но ведёт она в исходный каталог.
      expect((copied! as LinkNode).reference, '/home/src/real');
    });

    test('следуем — в приёмнике оказывается содержимое цели', () async {
      final operation = engine.copy();
      collectQuestions(operation);
      operation.start(TransferParams([await dir('/home/src')], await dir('/home/box'), followLinks: true));
      await operation.result;

      final copied = await disk.resolvePath().run('/home/box/src/link/inside.txt');

      expect(copied, isNotNull);
    });

    test('приёмник ссылку хранить не умеет — спрашивает, а не падает', () async {
      // Чужой приёмник: у ссылки нет байтового представления, и передать её
      // нечем.
      final other = InMemoryContentProvider([FakeEntry.directory('/remote')]);
      final target = (await other.resolvePath().run('/remote'))! as DirectoryNode;

      final operation = engine.copy();
      final questions = collectQuestions(operation);
      operation.start(TransferParams([await at('/home/src/link')], target));
      await operation.result;

      expect(questions, hasLength(1));
      expect(questions.single, contains('link'));
    });

    test('«пропустить все» больше не спрашивает', () async {
      disk.add(FakeEntry.link('/home/src/second', '/home/src/real'));
      final other = InMemoryContentProvider([FakeEntry.directory('/remote')]);
      final target = (await other.resolvePath().run('/remote'))! as DirectoryNode;

      final operation = engine.copy();
      final questions = <String>[];
      operation.requests.listen((request) {
        questions.add(request.message);
        request.respond(OperationRequestOption.skipAll);
      });

      operation.start(TransferParams([await dir('/home/src')], target));
      await operation.result;

      // Спросили один раз — на каталоге со ссылками это и есть разница между
      // «прозрачно» и «замучил вопросами».
      expect(questions, hasLength(1));
    });

    test('ссылка внутрь копируемого каталога не уводит в бесконечность', () async {
      // `src/loop → src`: пойти по ней — значит копировать себя в себя.
      disk.add(FakeEntry.link('/home/src/loop', '/home/src'));

      final operation = engine.copy();
      final questions = collectQuestions(operation);

      operation.start(TransferParams([await dir('/home/src')], await dir('/home/box'), followLinks: true));
      await operation.result.timeout(const Duration(seconds: 10));

      expect(questions, hasLength(1));
      expect(questions.single, contains('points into the directory'));
    });
  });

  group('стратегии', () {
    test('перенос в пределах провайдера идёт переименованием', () async {
      await engine.move().run(TransferParams([await node('/home/notes.txt')], await directory('/home/bin')));

      expect(provider.renamed, ['/home/notes.txt']);
      // Переименование переносит объект целиком: копировать нечего.
      expect(provider.copied, isEmpty);
      expect(await provider.resolvePath().run('/home/bin/notes.txt'), isNotNull);
      expect(await provider.resolvePath().run('/home/notes.txt'), isNull);
    });

    test('без переименования объект копируется и удаляется', () async {
      // Так ведёт себя перенос между дисками: `EXDEV` — это false из примитива.
      provider.renames = false;

      await engine.move().run(TransferParams([await node('/home/notes.txt')], await directory('/home/bin')));

      expect(provider.renamed, isEmpty);
      expect(provider.copied, ['/home/notes.txt']);
      expect(await provider.resolvePath().run('/home/bin/notes.txt'), isNotNull);
      expect(await provider.resolvePath().run('/home/notes.txt'), isNull);
    });

    test('копирование переименованием не пользуется', () async {
      await engine.copy().run(TransferParams([await node('/home/notes.txt')], await directory('/home/bin')));

      expect(provider.renamed, isEmpty);
      expect(provider.copied, ['/home/notes.txt']);
      expect(await provider.resolvePath().run('/home/notes.txt'), isNotNull);
    });

    test('каталог движок создаёт и обходит сам, а не отдаёт провайдеру', () async {
      await engine.copy().run(TransferParams([await node('/home/docs')], await directory('/home/bin')));

      // Провайдер копировал только файлы: каталоги создавал движок, поштучно —
      // иначе о ходе работы внутри дерева было бы нечего сказать.
      expect(provider.copied, ['/home/docs/nested/deep.txt', '/home/docs/readme.md']);
      expect(await provider.resolvePath().run('/home/bin/docs/nested/deep.txt'), isNotNull);
      expect(await provider.resolvePath().run('/home/bin/docs/readme.md'), isNotNull);
    });

    test('удаление в корзину — одно действие, мимо корзины — обход', () async {
      await engine.remove().run(RemoveParams([await node('/home/docs')]));
      expect(provider.trashed, ['/home/docs']);
      expect(provider.deleted, isEmpty);

      final other = InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/docs/readme.md', size: 5),
      ])..hasTrash = false;
      final target = (await other.resolvePath().run('/home/docs'))! as DirectoryNode;

      await engine.remove().run(RemoveParams([target]));

      // Корзины нет — движок удаляет поддерево снизу вверх, показывая каждый шаг.
      expect(other.trashed, isEmpty);
      expect(other.deleted, ['/home/docs/readme.md', '/home/docs']);
    });
  });

  group('ход внутри файла', () {
    test('байты провайдера двигают и его полосу, и общую', () async {
      // Копия средствами провайдера — единственная стратегия, где движок не
      // видит байт сам: рассказать о них может только провайдер.
      provider.copyChunkBytes = 4;
      final operation = engine.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([await node('/home/notes.txt')], await directory('/home/bin')));
      await operation.result;
      await pumpEventQueue();

      final partial = reports.where((report) => report.itemBytesTransferred > 0 && report.itemBytesTransferred < 10);
      expect(partial, isNotEmpty, reason: 'файл так и остался «нулём до конца»');
      expect(reports.map((report) => report.itemBytesTransferred), contains(10));
      // Ни байта дважды: добор по концу считает только то, о чём провайдер
      // промолчал.
      expect(reports.last.bytesTransferred, 10);
    });

    test('молчащий провайдер засчитывается целиком, как раньше', () async {
      final operation = engine.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([await node('/home/notes.txt')], await directory('/home/bin')));
      await operation.result;
      await pumpEventQueue();

      expect(reports.where((report) => report.itemBytesTransferred > 0 && report.itemBytesTransferred < 10), isEmpty);
      expect(reports.last.bytesTransferred, 10);
    });

    test('отмена посреди файла убирает недописанное', () async {
      provider.copyChunkBytes = 1;
      final operation = engine.copy();
      operation.requests.listen((request) => request.respond(OperationRequestOption.abort));

      // Просьба приходит, когда копия уже пошла: между объектами её перехватила
      // бы обычная контрольная точка, и до файла дело бы не дошло.
      var asked = false;
      final status = operation.status as SingleTransferOperationStatus;
      status.addListener(() {
        if (!asked && status.itemBytesTransferred > 0) {
          asked = true;
          operation.requestCancel();
        }
      });

      operation.start(TransferParams([await node('/home/notes.txt')], await directory('/home/bin')));

      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue();

      expect(asked, isTrue, reason: 'копия кончилась раньше, чем её успели прервать');
      // Половина файла под настоящим именем выглядит как целый файл.
      expect(await provider.resolvePath().run('/home/bin/notes.txt'), isNull);
    });
  });

  group('два провайдера', () {
    late InMemoryTreeProvider remote;

    setUp(() {
      remote = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/bin')]);
    });

    test('без байтового контракта переносить нечем, и об этом спрашивают', () async {
      final destination = (await remote.resolvePath().run('/home/bin'))! as DirectoryNode;
      final operation = engine.copy();
      final questions = collectQuestions(operation);

      operation.start(TransferParams([await node('/home/notes.txt')], destination));
      await operation.result;
      await pumpEventQueue();

      // Ни переименования, ни копирования средствами провайдера здесь нет,
      // а байтов ни одна из сторон не отдаёт: остаётся только признаться.
      expect(questions.single, FsError('/home/notes.txt', FsErrorKind.notSupported).message);
      expect(await remote.resolvePath().run('/home/bin/notes.txt'), isNull);
    });

    test('невозможный объект не прекращает работу над остальными', () async {
      remote.add(FakeEntry.file('/home/local.txt', size: 1));
      final destination = (await remote.resolvePath().run('/home/bin'))! as DirectoryNode;
      final foreign = await node('/home/notes.txt');
      final mine = (await remote.resolvePath().run('/home/local.txt'))!;

      final operation = engine.copy();
      final questions = collectQuestions(operation);
      operation.start(TransferParams([foreign, mine], destination));
      await operation.result;
      await pumpEventQueue();

      // Один источник чужой, другой свой: вопрос задан по первому, второй
      // скопирован.
      expect(questions, hasLength(1));
      expect(await remote.resolvePath().run('/home/bin/notes.txt'), isNull);
      expect(await remote.resolvePath().run('/home/bin/local.txt'), isNotNull);
    });

    test('приёмник только для чтения — работа не начинается', () async {
      final readOnly = _ReadOnlyProvider();
      final destination = DirectoryNode(provider: readOnly, name: 'archive.zip');

      final operation = engine.copy();

      operation.start(TransferParams([await node('/home/notes.txt')], destination));
      await expectLater(operation.result, throwsA(isA<FsError>()));
      expect(operation.state, OperationState.error);
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

    Future<DirectoryNode> remoteBin() async => (await remote.resolvePath().run('/home/bin'))! as DirectoryNode;

    /// Содержимое файла в приёмнике — тем же контрактом, каким его писали.
    Future<List<int>?> remoteContent(String path) async {
      final node = await remote.resolvePath().run(path);
      if (node == null) {
        return null;
      }
      final chunks = await (await remote.openRead(node)).toList();
      return [for (final chunk in chunks) ...chunk];
    }

    test('файл уходит в чужой провайдер вместе с содержимым', () async {
      final file = (await source.resolvePath().run('/home/notes.txt'))!;

      await engine.copy().run(TransferParams([file], await remoteBin()));

      expect(await remoteContent('/home/bin/notes.txt'), [7, 8, 9, 10]);
      // Ни переименования, ни копирования средствами провайдера тут быть
      // не могло: провайдеры разные.
      expect(source.renamed, isEmpty);
      expect(source.copied, isEmpty);
    });

    test('приёмник узнаёт размер заранее', () async {
      final file = (await source.resolvePath().run('/home/notes.txt'))!;

      await engine.copy().run(TransferParams([file], await remoteBin()));

      // FTP и HTTP просят размер вперёд — движок отдаёт его, когда знает.
      expect(remote.written['/home/bin/notes.txt'], 4);
    });

    test('каталог уезжает целиком, файлы в нём — потоком', () async {
      final docs = (await source.resolvePath().run('/home/docs'))!;

      await engine.copy().run(TransferParams([docs], await remoteBin()));

      expect(await remoteContent('/home/bin/docs/readme.md'), [1, 2, 3]);
    });

    test('перенос убирает исходный объект', () async {
      final file = (await source.resolvePath().run('/home/notes.txt'))!;

      await engine.move().run(TransferParams([file], await remoteBin()));

      expect(await remoteContent('/home/bin/notes.txt'), [7, 8, 9, 10]);
      expect(await source.resolvePath().run('/home/notes.txt'), isNull);
    });

    test('внутри большого файла видно движение', () async {
      source.add(FakeEntry.file('/home/big.bin', content: List.filled(50, 1)));
      final file = (await source.resolvePath().run('/home/big.bin'))!;

      final operation = engine.copy();
      final reports = ProgressLog.of(operation).reports;
      operation.start(TransferParams([file], await remoteBin()));
      await operation.result;
      await pumpEventQueue();

      // Объект всё это время один и тот же, а доля растёт: по объектам тут
      // было бы «0 из 1» до самого конца.
      final inside = reports
          .where((event) => event.bytesTransferred > 0 && event.bytesTransferred < 50)
          .map((event) => event.bytesTransferred);
      expect(inside, [10, 20, 30, 40]);
      expect(reports.last.bytesTransferred, 50);
      expect(reports.last.percent, 1);
    });

    test('отмена посреди файла не оставляет обрезанного', () async {
      source.add(FakeEntry.file('/home/big.bin', content: List.filled(50, 1)));
      final file = (await source.resolvePath().run('/home/big.bin'))!;

      late final Operation<Object?, void> operation;
      // Первый кусок уже записан — в приёмнике лежит начало файла.
      source.onChunk = () => operation.cancel();
      operation = engine.copy()..start(TransferParams([file], await remoteBin()));

      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue();

      expect(await remote.resolvePath().run('/home/bin/big.bin'), isNull);
    });

    test('оборвавшаяся передача не оставляет обрезанного файла', () async {
      final broken = _BreakingReadProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/big.bin', content: List.filled(50, 1)),
      ]);
      final file = (await broken.resolvePath().run('/home/big.bin'))!;

      final operation = engine.copy();
      final questions = collectQuestions(operation);
      operation.start(TransferParams([file], await remoteBin()));
      await operation.result;
      await pumpEventQueue();

      // Половина файла под настоящим именем выглядела бы как целый файл.
      expect(questions, hasLength(1));
      expect(await remote.resolvePath().run('/home/bin/big.bin'), isNull);
    });

    test('ошибка байтов доводится до общего вида, а работа идёт дальше', () async {
      final broken = _BreakingReadProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/big.bin', content: List.filled(50, 1)),
        FakeEntry.file('/home/small.bin', content: const []),
      ]);
      final first = (await broken.resolvePath().run('/home/big.bin'))!;
      final second = (await broken.resolvePath().run('/home/small.bin'))!;

      final operation = engine.copy();
      final questions = collectQuestions(operation);
      operation.start(TransferParams([first, second], await remoteBin()));
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

    Future<(Operation<Object?, void>, InMemoryTreeProvider)> startCopy() async {
      final disk = InMemoryTreeProvider(many());
      final sources = [for (var i = 0; i < 20; i++) (await disk.resolvePath().run('/home/file-$i.txt'))!];
      final target = (await disk.resolvePath().run('/home/bin'))! as DirectoryNode;
      return (engine.copy()..start(TransferParams(sources, target)), disk);
    }

    test('спрашивает подтверждение, а не прерывает молча', () async {
      final (operation, _) = await startCopy();
      final questions = <OperationRequest>[];
      operation.requests.listen(questions.add);

      operation.requestCancel();
      await pumpEventQueue();

      expect(questions, hasLength(1));
      expect(questions.single.options, [OperationRequestOption.abort, OperationRequestOption.resume]);
      // Enter прерывает, Esc — отказывается прерывать.
      expect(questions.single.enterOption, OperationRequestOption.abort);
      expect(questions.single.escapeOption, OperationRequestOption.resume);

      questions.single.respond(OperationRequestOption.abort);
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

      question!.respond(OperationRequestOption.resume);
      await operation.result;
    });

    test('«Cancel» возвращает к работе, и она доходит до конца', () async {
      final (operation, disk) = await startCopy();
      operation.requests.listen((request) => request.respond(OperationRequestOption.resume));

      operation.requestCancel();
      await operation.result;

      expect(disk.copied, hasLength(20));
      expect(operation.state, OperationState.complete);
    });

    test('«Abort» прекращает работу на том, что успели', () async {
      final (operation, disk) = await startCopy();
      operation.requests.listen((request) => request.respond(OperationRequestOption.abort));

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
      final sources = [for (var i = 0; i < 20; i++) (await disk.resolvePath().run('/home/file-$i.txt'))!];
      final operation = engine.remove();
      final questions = <OperationRequest>[];
      operation.requests.listen(questions.add);
      operation.start(RemoveParams(sources, toTrash: false));

      operation.requestCancel();
      await pumpEventQueue();

      expect(questions.single.message, 'Abort the operation?');
      questions.single.respond(OperationRequestOption.abort);
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
      final shown = await provider.getDirectoryListing().run(ListingParams(docs));

      await engine.copy().run(TransferParams([docs], await directory('/home/bin')));

      // Обход движка читает то же самое, но мимо узла: иначе в панели вместо
      // её списка (с «..» и без скрытых) оказался бы список для копирования.
      expect(docs.nodes, orderedEquals(shown));
      expect(docs.nodes.first, isA<ParentDirNode>());
    });

    test('счётчики доходят до конца и на переименовании, и на обходе', () async {
      final operation =
          engine.copy()..start(
            TransferParams([await node('/home/docs'), await node('/home/notes.txt')], await directory('/home/bin')),
          );
      final reports = ProgressLog.of(operation).reports;

      await operation.result;
      await pumpEventQueue();

      // Каталог с тремя вложенными объектами и файл — пять объектов.
      final counted = reports.where((report) => report.totalIsFinal);
      expect(counted.last.itemsTotal, 5);
      expect(reports.last.itemsTransferred, reports.last.itemsTotal);
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
/// Приёмник, который применяет накопленное разом, — как архив.
class _BatchingProvider extends InMemoryContentProvider implements BatchedWrites {
  _BatchingProvider(super.entries);

  final List<String> calls = [];

  @override
  String get writesStageName => 'repacking archive';

  @override
  Future<void> beginWrites() async => calls.add('begin');

  @override
  Future<void> endWrites() async => calls.add('end');
}

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

/// Провайдер, который не умеет убирать поддерево одним действием: движку
/// приходится обходить его поштучно — как по SFTP.
class _SlowDeleteProvider extends InMemoryContentProvider {
  _SlowDeleteProvider(super.entries);

  @override
  Future<bool> deleteTree(FsNode node) async => false;
}
