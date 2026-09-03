import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Работу делает движок, провайдер даёт ему примитивы: своего состояния
/// у движка нет, поэтому он один на все тесты файла.
const editor = TreeTransferEngine();

/// Копирование и перенос на настоящей файловой системе: во временном каталоге.
void main() {
  late Directory temp;
  late String root;
  late String target;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_transfer');
    root = await temp.resolveSymbolicLinks();

    await Directory(p.join(root, 'docs')).create();
    await Directory(p.join(root, 'docs', 'nested')).create();
    await File(p.join(root, 'docs', 'readme.md')).writeAsString('hello');
    await File(p.join(root, 'docs', 'nested', 'deep.txt')).writeAsString('deep');
    await File(p.join(root, 'notes.txt')).writeAsString('текст');
    await File(p.join(root, 'report.txt')).writeAsString('отчёт');
    await Link(p.join(root, 'link-to-notes')).create(p.join(root, 'notes.txt'));

    target = p.join(root, 'target');
    await Directory(target).create();

    provider = LocalTreeProvider(homePath: root, readInIsolate: false);
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

  Future<DirectoryNode> targetDir() async => (await provider.resolvePath().run(target))! as DirectoryNode;

  /// Отвечает на все вопросы операции одинаково.
  void answerWith(Operation<Object?, void> operation, OperationRequestOption option) {
    operation.requests.listen((request) => request.respond(option));
  }

  group('копирование', () {
    test('файл появляется в приёмнике и остаётся в источнике', () async {
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['notes.txt']!], await targetDir()));

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
      expect(await File(p.join(root, 'notes.txt')).exists(), isTrue);
    });

    test('каталог копируется вместе со всем содержимым', () async {
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['docs']!], await targetDir()));

      expect(await File(p.join(target, 'docs', 'readme.md')).readAsString(), 'hello');
      expect(await File(p.join(target, 'docs', 'nested', 'deep.txt')).readAsString(), 'deep');
    });

    test('ссылка копируется ссылкой, а не тем, куда ведёт', () async {
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['link-to-notes']!], await targetDir()));

      final copied = p.join(target, 'link-to-notes');
      expect(FileSystemEntity.isLinkSync(copied), isTrue);
      expect(await Link(copied).target(), p.join(root, 'notes.txt'));
    });

    test('копируются все переданные объекты', () async {
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['notes.txt']!, nodes['report.txt']!], await targetDir()));

      expect(await File(p.join(target, 'notes.txt')).exists(), isTrue);
      expect(await File(p.join(target, 'report.txt')).exists(), isTrue);
    });

    test('сообщает о ходе работы', () async {
      final nodes = await listRoot();
      final operation = editor.copy();
      final log = ProgressLog.of(operation);

      operation.start(TransferParams([nodes['notes.txt']!, nodes['report.txt']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      expect(log.reports.map((report) => report.message), contains('notes.txt'));
      expect(log.last.message, 'Done');
    });

    test('счётчик обработанного растёт, а не стоит на месте', () async {
      final nodes = await listRoot();
      final operation = editor.copy();
      final log = ProgressLog.of(operation);

      operation.start(TransferParams([nodes['docs']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      // В каталоге четыре объекта: он сам, вложенный каталог и два файла.
      expect(log.last.itemsTransferred, 4);
      // Между началом и концом счётчик проходил промежуточные значения.
      expect(log.reports.map((report) => report.itemsTransferred).toSet().length, greaterThan(1));
    });

    test('общее количество считается фоном и в конце становится окончательным', () async {
      final nodes = await listRoot();
      final operation = editor.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([nodes['docs']!, nodes['notes.txt']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      // Работа началась, не дожидаясь конца подсчёта: пока он идёт, общее
      // число — нижняя оценка, и это видно.
      expect(reports.first.totalIsFinal, isFalse);
      expect(reports.first.itemsTotal, lessThan(5));

      // К концу оно точное: каталог с тремя вложенными объектами и файл.
      final counted = reports.where((report) => report.totalIsFinal);
      expect(counted.last.itemsTotal, 5);
      expect(reports.last.percent, 1);
    });

    test('объём задания и перенесённое считаются в байтах', () async {
      final nodes = await listRoot();
      final operation = editor.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([nodes['notes.txt']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      // «текст» в utf-8 — десять байт.
      expect(reports.last.bytesTransferred, 10);
      expect(reports.last.bytesTotal, 10);
    });

    test('в строке источника стоит объект задания, а имя файла — в своей строке', () async {
      final nodes = await listRoot();
      final operation = editor.copy();
      final log = ProgressLog.of(operation);

      operation.start(TransferParams([nodes['docs']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      // Копируется каталог — он и стоит в строке источника всё время работы.
      // Пустое — «сказать пока нечего»: это до того, как работа взялась за
      // первый источник.
      final named = log.reports
          .map((report) => report.message)
          .where((message) => message.isNotEmpty && message != 'Done');
      expect(named, everyElement('docs'));
      // А по его содержимому бежит имя текущего файла — это разные строки окна.
      expect(
        log.reports.any((report) => report.itemName == 'readme.md' || report.itemName == 'deep.txt'),
        isTrue,
        reason: 'имя файла показывается отдельно от имени задания',
      );
    });

    test('перенос переименованием доводит счётчик до конца', () async {
      final nodes = await listRoot();
      final operation = editor.move();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([nodes['docs']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      // Переименование переносит поддерево одним действием: поштучно объекты
      // не проходили, но задание выполнено целиком, и счётчик это показывает.
      expect(reports.last.percent, 1);
      expect(reports.last.itemsTransferred, reports.last.itemsTotal);
    });
  });

  group('ход внутри файла', () {
    /// Размер, на котором видно движение: несколько кусков по полмегабайта.
    const size = 8 * 1024 * 1024;

    /// Провайдер с известным порогом: значение по умолчанию тут ни при чём —
    /// проверяется, что порог вообще работает.
    LocalTreeProvider providerWith(int threshold) => LocalTreeProvider(
      homePath: root,
      readInIsolate: false,
      settings: () => LocalFsSettings(copyProgressMinBytes: threshold),
    );

    Future<(FsNode, DirectoryNode)> bigFile(LocalTreeProvider disk) async {
      await File(p.join(root, 'big.bin')).writeAsBytes(List<int>.filled(size, 7), flush: true);
      final node = (await disk.resolvePath().run(p.join(root, 'big.bin')))!;
      return (node, (await disk.resolvePath().run(target))! as DirectoryNode);
    }

    test('выше порога — байты идут по ходу дела', () async {
      final disk = providerWith(1024);
      final (node, destination) = await bigFile(disk);
      final operation = editor.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([node], destination));
      await operation.result;
      await pumpEventQueue();

      final partial = reports.where((report) => report.itemBytesTransferred > 0 && report.itemBytesTransferred < size);
      expect(partial, isNotEmpty, reason: 'полоса файла так и стояла на нуле');
      // Сумма сходится с размером: ни байта дважды, ни байта мимо.
      expect(reports.last.bytesTransferred, size);
      expect(await File(p.join(target, 'big.bin')).length(), size);
    });

    test('ниже порога — копия одним действием, как раньше', () async {
      // Порог выше самого файла: ход внутри него не показывается вовсе.
      final disk = providerWith(size * 2);
      final (node, destination) = await bigFile(disk);
      final operation = editor.copy();
      final reports = ProgressLog.of(operation).reports;

      operation.start(TransferParams([node], destination));
      await operation.result;
      await pumpEventQueue();

      expect(reports.where((report) => report.itemBytesTransferred > 0 && report.itemBytesTransferred < size), isEmpty);
      // Объём всё равно засчитан целиком — по концу копии.
      expect(reports.last.bytesTransferred, size);
      expect(await File(p.join(target, 'big.bin')).length(), size);
    });
  });

  group('имя уже занято', () {
    setUp(() async {
      await File(p.join(target, 'notes.txt')).writeAsString('чужое');
    });

    test('без ответа существующий файл остаётся нетронутым', () async {
      final nodes = await listRoot();

      // Спросить некого: операция берёт ответ по умолчанию — пропустить.
      await editor.copy().run(TransferParams([nodes['notes.txt']!], await targetDir()));

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'чужое');
    });

    test('перезапись заменяет содержимое', () async {
      final nodes = await listRoot();
      final operation = editor.copy();
      answerWith(operation, TransferAnswers.overwrite);

      operation.start(TransferParams([nodes['notes.txt']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
    });

    test('«перезаписать все» больше не спрашивает', () async {
      await File(p.join(target, 'report.txt')).writeAsString('чужое');
      final nodes = await listRoot();
      final operation = editor.copy();
      var questions = 0;
      operation.requests.listen((request) {
        questions++;
        request.respond(TransferAnswers.overwriteAll);
      });

      operation.start(TransferParams([nodes['notes.txt']!, nodes['report.txt']!], await targetDir()));

      await operation.result;
      await pumpEventQueue();

      expect(questions, 1);
      expect(await File(p.join(target, 'report.txt')).readAsString(), 'отчёт');
    });

    test('отмена прекращает работу', () async {
      final nodes = await listRoot();
      final operation = editor.copy();
      answerWith(operation, TransferAnswers.cancel);

      operation.start(TransferParams([nodes['notes.txt']!, nodes['report.txt']!], await targetDir()));
      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
      expect(await File(p.join(target, 'report.txt')).exists(), isFalse);
    });

    test('каталог поверх каталога сливается, а не заменяется', () async {
      await Directory(p.join(target, 'docs')).create();
      await File(p.join(target, 'docs', 'stale.txt')).writeAsString('старое');
      final nodes = await listRoot();
      final operation = editor.copy();
      answerWith(operation, TransferAnswers.overwrite);

      operation.start(TransferParams([nodes['docs']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      // Чужого содержимого в задании не было: совпало имя каталога, а не то,
      // что внутри. Так ведут себя mc, Total Commander и Far.
      expect(await File(p.join(target, 'docs', 'stale.txt')).readAsString(), 'старое');
      expect(await File(p.join(target, 'docs', 'readme.md')).exists(), isTrue);
      expect(await File(p.join(target, 'docs', 'nested', 'deep.txt')).exists(), isTrue);
    });

    test('о совпавшем файле внутри спрашивают, а «пропустить» его сохраняет', () async {
      await Directory(p.join(target, 'docs')).create();
      await File(p.join(target, 'docs', 'readme.md')).writeAsString('своё');
      final nodes = await listRoot();
      final operation = editor.copy();
      final questions = <String>[];
      operation.requests.listen((request) {
        questions.add(request.message);
        request.respond(TransferAnswers.skip);
      });

      operation.start(TransferParams([nodes['docs']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      expect(questions.single, contains('readme.md'));
      expect(await File(p.join(target, 'docs', 'readme.md')).readAsString(), 'своё');
      // Остальное доехало: пропустили один файл, а не весь каталог.
      expect(await File(p.join(target, 'docs', 'nested', 'deep.txt')).exists(), isTrue);
    });
  });

  group('перенос', () {
    test('объект исчезает из источника', () async {
      final nodes = await listRoot();

      await editor.move().run(TransferParams([nodes['notes.txt']!], await targetDir()));

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
    });

    test('каталог переносится вместе с содержимым', () async {
      final nodes = await listRoot();

      await editor.move().run(TransferParams([nodes['docs']!], await targetDir()));

      expect(await Directory(p.join(root, 'docs')).exists(), isFalse);
      expect(await File(p.join(target, 'docs', 'nested', 'deep.txt')).readAsString(), 'deep');
    });

    test('пропущенный объект остаётся на месте', () async {
      await File(p.join(target, 'notes.txt')).writeAsString('чужое');
      final nodes = await listRoot();
      final operation = editor.move();
      answerWith(operation, TransferAnswers.skip);

      operation.start(TransferParams([nodes['notes.txt']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      expect(await File(p.join(root, 'notes.txt')).exists(), isTrue);
      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'чужое');
    });

    test('перенос ссылки не трогает то, куда она ведёт', () async {
      final nodes = await listRoot();

      await editor.move().run(TransferParams([nodes['link-to-notes']!], await targetDir()));

      expect(FileSystemEntity.isLinkSync(p.join(target, 'link-to-notes')), isTrue);
      expect(await File(p.join(root, 'notes.txt')).exists(), isTrue);
    });
  });

  group('между провайдерами', () {
    late LocalTreeProvider remote;

    setUp(() {
      // Второй экземпляр — для движка это чужой провайдер: ни переименования,
      // ни `File.copy` между ними нет, остаётся поток.
      remote = LocalTreeProvider(homePath: root, readInIsolate: false);
    });

    Future<DirectoryNode> remoteTarget() async => (await remote.resolvePath().run(target))! as DirectoryNode;

    test('файл переносится потоком', () async {
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['notes.txt']!], await remoteTarget()));

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
    });

    test('каталог переносится вместе со всем содержимым', () async {
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['docs']!], await remoteTarget()));

      expect(await File(p.join(target, 'docs', 'readme.md')).readAsString(), 'hello');
      expect(await File(p.join(target, 'docs', 'nested', 'deep.txt')).readAsString(), 'deep');
    });

    test('ссылка уходит ссылкой и к чужому приёмнику', () async {
      // Байтов у ссылки нет, потоком её не передать — зато можно отдать строку
      // с целью, и приёмник заведёт ссылку сам. Это и есть тот случай, ради
      // которого `/etc/nginx` копируется с сервера молча.
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['link-to-notes']!], await remoteTarget()));

      final copied = p.join(target, 'link-to-notes');
      expect(await FileSystemEntity.isLink(copied), isTrue, reason: 'приехала ссылка, а не копия файла');
      expect(await Link(copied).target(), p.join(root, 'notes.txt'), reason: 'цель перенесена как есть');
    });

    test('относительная цель остаётся относительной', () async {
      await Link(p.join(root, 'docs', 'near')).create('readme.md');
      final docs = (await provider.resolvePath().run(p.join(root, 'docs')))! as DirectoryNode;
      final nodes = await provider.getDirectoryListing().run(ListingParams(docs));
      final near = nodes.firstWhere((node) => node.name == 'near');

      await editor.copy().run(TransferParams([near], await remoteTarget()));

      // Переписывать цель мы не вправе: что человек имел в виду, знает он.
      expect(await Link(p.join(target, 'near')).target(), 'readme.md');
    });

    test('битая ссылка переносится и остаётся битой', () async {
      await Link(p.join(root, 'dangling')).create('/nowhere/at/all');
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['dangling']!], await remoteTarget()));

      final copied = p.join(target, 'dangling');
      expect(await FileSystemEntity.isLink(copied), isTrue);
      expect(await Link(copied).target(), '/nowhere/at/all');
      expect(await File(copied).exists(), isFalse, reason: 'битой она и была');
    });

    test('следуем по ссылке — приезжает файл: цели в чужом дереве нет', () async {
      final nodes = await listRoot();

      await editor.copy().run(TransferParams([nodes['link-to-notes']!], await remoteTarget(), followLinks: true));

      final copied = p.join(target, 'link-to-notes');
      expect(FileSystemEntity.isLinkSync(copied), isFalse);
      expect(await File(copied).readAsString(), 'текст');
    });

    test('перенос убирает исходный объект', () async {
      final nodes = await listRoot();

      await editor.move().run(TransferParams([nodes['notes.txt']!], await remoteTarget()));

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
    });
  });

  group('невозможные задания', () {
    test('каталог нельзя скопировать внутрь самого себя', () async {
      final nodes = await listRoot();
      final inside = (await provider.resolvePath().run(p.join(root, 'docs', 'nested')))! as DirectoryNode;

      final operation = editor.copy();
      final messages = <String>[];
      operation.requests.listen((request) {
        messages.add(request.message);
        request.respond(TransferAnswers.skip);
      });

      operation.start(TransferParams([nodes['docs']!], inside));
      await operation.result;
      await pumpEventQueue();

      expect(messages.single, contains('into itself'));
      expect(await Directory(p.join(root, 'docs', 'nested', 'docs')).exists(), isFalse);
    });

    test('копирование в тот же каталог отклоняется', () async {
      final nodes = await listRoot();
      final sameDir = (await provider.resolvePath().run(root))! as DirectoryNode;

      final operation = editor.copy();
      final messages = <String>[];
      operation.requests.listen((request) {
        messages.add(request.message);
        request.respond(TransferAnswers.skip);
      });

      operation.start(TransferParams([nodes['notes.txt']!], sameDir));
      await operation.result;
      await pumpEventQueue();

      expect(messages.single, FsError(p.join(root, 'notes.txt'), FsErrorKind.alreadyExists).message);
    });

    test('ошибка на одном объекте не останавливает остальные', () async {
      final nodes = await listRoot();
      // Объект исчез уже после того, как каталог был прочитан.
      await File(p.join(root, 'notes.txt')).delete();

      final operation = editor.copy();
      answerWith(operation, TransferAnswers.skip);
      operation.start(TransferParams([nodes['notes.txt']!, nodes['report.txt']!], await targetDir()));
      await operation.result;
      await pumpEventQueue();

      expect(await File(p.join(target, 'report.txt')).exists(), isTrue);
    });
  });
}
