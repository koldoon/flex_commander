import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/modules/local_fs/local_fs_settings.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
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
    final dir = (await provider.resolvePath(root).result)! as DirectoryNode;
    final nodes = await provider.getDirectoryListing(dir).result;
    return {for (final node in nodes) node.name: node};
  }

  Future<DirectoryNode> targetDir() async => (await provider.resolvePath(target).result)! as DirectoryNode;

  /// Отвечает на все вопросы операции одинаково.
  void answerWith(AsyncOperation<void> operation, OperationRequestOption option) {
    operation.requests.listen((request) => request.respond(option));
  }

  group('копирование', () {
    test('файл появляется в приёмнике и остаётся в источнике', () async {
      final nodes = await listRoot();

      await editor.copy([nodes['notes.txt']!], await targetDir()).result;

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
      expect(await File(p.join(root, 'notes.txt')).exists(), isTrue);
    });

    test('каталог копируется вместе со всем содержимым', () async {
      final nodes = await listRoot();

      await editor.copy([nodes['docs']!], await targetDir()).result;

      expect(await File(p.join(target, 'docs', 'readme.md')).readAsString(), 'hello');
      expect(await File(p.join(target, 'docs', 'nested', 'deep.txt')).readAsString(), 'deep');
    });

    test('ссылка копируется ссылкой, а не тем, куда ведёт', () async {
      final nodes = await listRoot();

      await editor.copy([nodes['link-to-notes']!], await targetDir()).result;

      final copied = p.join(target, 'link-to-notes');
      expect(FileSystemEntity.isLinkSync(copied), isTrue);
      expect(await Link(copied).target(), p.join(root, 'notes.txt'));
    });

    test('копируются все переданные объекты', () async {
      final nodes = await listRoot();

      await editor.copy([nodes['notes.txt']!, nodes['report.txt']!], await targetDir()).result;

      expect(await File(p.join(target, 'notes.txt')).exists(), isTrue);
      expect(await File(p.join(target, 'report.txt')).exists(), isTrue);
    });

    test('сообщает о ходе работы', () async {
      final nodes = await listRoot();
      final operation = editor.copy([nodes['notes.txt']!, nodes['report.txt']!], await targetDir());
      final messages = <String>[];
      operation.progress.listen((event) => messages.add(event.message));

      await operation.result;
      await pumpEventQueue();

      expect(messages, contains('Copying notes.txt…'));
      expect(messages.last, 'Done');
    });

    test('счётчик обработанного растёт, а не стоит на месте', () async {
      final nodes = await listRoot();
      final operation = editor.copy([nodes['docs']!], await targetDir());
      final processed = <int>[];
      operation.progress.listen((event) => processed.add(event.processed));

      await operation.result;
      await pumpEventQueue();

      // В каталоге четыре объекта: он сам, вложенный каталог и два файла.
      expect(processed.last, 4);
      // Между началом и концом счётчик проходил промежуточные значения.
      expect(processed.toSet().length, greaterThan(1));
    });

    test('общее количество считается фоном и в конце становится окончательным', () async {
      final nodes = await listRoot();
      final operation = editor.copy([nodes['docs']!, nodes['notes.txt']!], await targetDir());
      final reports = <OperationProgress>[];
      operation.progress.listen(reports.add);

      await operation.result;
      await pumpEventQueue();

      // Работа началась, не дожидаясь конца подсчёта: пока он идёт, общее
      // число — нижняя оценка, и это видно.
      expect(reports.first.totalIsFinal, isFalse);
      expect(reports.first.total, lessThan(5));

      // К концу оно точное: каталог с тремя вложенными объектами и файл.
      final counted = reports.where((event) => event.totalIsFinal);
      expect(counted.last.total, 5);
      expect(reports.last.percent, 1);
    });

    test('объём задания и перенесённое считаются в байтах', () async {
      final nodes = await listRoot();
      final operation = editor.copy([nodes['notes.txt']!], await targetDir());
      final reports = <OperationProgress>[];
      operation.progress.listen(reports.add);

      await operation.result;
      await pumpEventQueue();

      // «текст» в utf-8 — десять байт.
      expect(reports.last.bytes, 10);
      expect(reports.last.totalBytes, 10);
    });

    test('в сообщении видно имя объекта, который копируется сейчас', () async {
      final nodes = await listRoot();
      final operation = editor.copy([nodes['docs']!], await targetDir());
      final messages = <String>[];
      operation.progress.listen((event) => messages.add(event.message));

      await operation.result;
      await pumpEventQueue();

      // Имя вложенного файла, а не только имя всего задания.
      expect(messages.any((message) => message.contains('readme.md') || message.contains('deep.txt')), isTrue);
    });

    test('перенос переименованием доводит счётчик до конца', () async {
      final nodes = await listRoot();
      final operation = editor.move([nodes['docs']!], await targetDir());
      final reports = <OperationProgress>[];
      operation.progress.listen(reports.add);

      await operation.result;
      await pumpEventQueue();

      // Переименование переносит поддерево одним действием: поштучно объекты
      // не проходили, но задание выполнено целиком, и счётчик это показывает.
      expect(reports.last.percent, 1);
      expect(reports.last.processed, reports.last.total);
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
      final node = (await disk.resolvePath(p.join(root, 'big.bin')).result)!;
      return (node, (await disk.resolvePath(target).result)! as DirectoryNode);
    }

    test('выше порога — байты идут по ходу дела', () async {
      final disk = providerWith(1024);
      final (node, destination) = await bigFile(disk);
      final operation = editor.copy([node], destination);
      final reports = <OperationProgress>[];
      operation.progress.listen(reports.add);

      await operation.result;
      await pumpEventQueue();

      final partial = reports.where((report) => report.itemBytes > 0 && report.itemBytes < size);
      expect(partial, isNotEmpty, reason: 'полоса файла так и стояла на нуле');
      // Сумма сходится с размером: ни байта дважды, ни байта мимо.
      expect(reports.last.bytes, size);
      expect(await File(p.join(target, 'big.bin')).length(), size);
    });

    test('ниже порога — копия одним действием, как раньше', () async {
      // Порог выше самого файла: ход внутри него не показывается вовсе.
      final disk = providerWith(size * 2);
      final (node, destination) = await bigFile(disk);
      final operation = editor.copy([node], destination);
      final reports = <OperationProgress>[];
      operation.progress.listen(reports.add);

      await operation.result;
      await pumpEventQueue();

      expect(reports.where((report) => report.itemBytes > 0 && report.itemBytes < size), isEmpty);
      // Объём всё равно засчитан целиком — по концу копии.
      expect(reports.last.bytes, size);
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
      await editor.copy([nodes['notes.txt']!], await targetDir()).result;

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'чужое');
    });

    test('перезапись заменяет содержимое', () async {
      final nodes = await listRoot();
      final operation = editor.copy([nodes['notes.txt']!], await targetDir());
      answerWith(operation, OperationRequestOption.overwrite);

      await operation.result;
      await pumpEventQueue();

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
    });

    test('«перезаписать все» больше не спрашивает', () async {
      await File(p.join(target, 'report.txt')).writeAsString('чужое');
      final nodes = await listRoot();
      final operation = editor.copy([nodes['notes.txt']!, nodes['report.txt']!], await targetDir());
      var questions = 0;
      operation.requests.listen((request) {
        questions++;
        request.respond(OperationRequestOption.overwriteAll);
      });

      await operation.result;
      await pumpEventQueue();

      expect(questions, 1);
      expect(await File(p.join(target, 'report.txt')).readAsString(), 'отчёт');
    });

    test('отмена прекращает работу', () async {
      final nodes = await listRoot();
      final operation = editor.copy([nodes['notes.txt']!, nodes['report.txt']!], await targetDir());
      answerWith(operation, OperationRequestOption.cancel);

      await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
      expect(await File(p.join(target, 'report.txt')).exists(), isFalse);
    });

    test('перезапись каталога не оставляет старого содержимого', () async {
      await Directory(p.join(target, 'docs')).create();
      await File(p.join(target, 'docs', 'stale.txt')).writeAsString('старое');
      final nodes = await listRoot();
      final operation = editor.copy([nodes['docs']!], await targetDir());
      answerWith(operation, OperationRequestOption.overwrite);

      await operation.result;
      await pumpEventQueue();

      expect(await File(p.join(target, 'docs', 'stale.txt')).exists(), isFalse);
      expect(await File(p.join(target, 'docs', 'readme.md')).exists(), isTrue);
    });
  });

  group('перенос', () {
    test('объект исчезает из источника', () async {
      final nodes = await listRoot();

      await editor.move([nodes['notes.txt']!], await targetDir()).result;

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
    });

    test('каталог переносится вместе с содержимым', () async {
      final nodes = await listRoot();

      await editor.move([nodes['docs']!], await targetDir()).result;

      expect(await Directory(p.join(root, 'docs')).exists(), isFalse);
      expect(await File(p.join(target, 'docs', 'nested', 'deep.txt')).readAsString(), 'deep');
    });

    test('пропущенный объект остаётся на месте', () async {
      await File(p.join(target, 'notes.txt')).writeAsString('чужое');
      final nodes = await listRoot();
      final operation = editor.move([nodes['notes.txt']!], await targetDir());
      answerWith(operation, OperationRequestOption.skip);

      await operation.result;
      await pumpEventQueue();

      expect(await File(p.join(root, 'notes.txt')).exists(), isTrue);
      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'чужое');
    });

    test('перенос ссылки не трогает то, куда она ведёт', () async {
      final nodes = await listRoot();

      await editor.move([nodes['link-to-notes']!], await targetDir()).result;

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

    Future<DirectoryNode> remoteTarget() async => (await remote.resolvePath(target).result)! as DirectoryNode;

    test('файл переносится потоком', () async {
      final nodes = await listRoot();

      await editor.copy([nodes['notes.txt']!], await remoteTarget()).result;

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
    });

    test('каталог переносится вместе со всем содержимым', () async {
      final nodes = await listRoot();

      await editor.copy([nodes['docs']!], await remoteTarget()).result;

      expect(await File(p.join(target, 'docs', 'readme.md')).readAsString(), 'hello');
      expect(await File(p.join(target, 'docs', 'nested', 'deep.txt')).readAsString(), 'deep');
    });

    test('ссылку чужому приёмнику передать нечем — по умолчанию пропускается', () async {
      // Байтового представления у ссылки нет, а подменять её содержимым цели
      // молча нельзя: это разные вещи и по размеру, и по смыслу. Окна здесь
      // нет, поэтому берётся ответ по умолчанию — «пропустить».
      final nodes = await listRoot();

      await editor.copy([nodes['link-to-notes']!], await remoteTarget()).result;

      expect(await File(p.join(target, 'link-to-notes')).exists(), isFalse);
    });

    test('следуем по ссылке — приезжает файл: цели в чужом дереве нет', () async {
      final nodes = await listRoot();

      await editor.copy([nodes['link-to-notes']!], await remoteTarget(), followLinks: true).result;

      final copied = p.join(target, 'link-to-notes');
      expect(FileSystemEntity.isLinkSync(copied), isFalse);
      expect(await File(copied).readAsString(), 'текст');
    });

    test('перенос убирает исходный объект', () async {
      final nodes = await listRoot();

      await editor.move([nodes['notes.txt']!], await remoteTarget()).result;

      expect(await File(p.join(target, 'notes.txt')).readAsString(), 'текст');
      expect(await File(p.join(root, 'notes.txt')).exists(), isFalse);
    });
  });

  group('невозможные задания', () {
    test('каталог нельзя скопировать внутрь самого себя', () async {
      final nodes = await listRoot();
      final inside = (await provider.resolvePath(p.join(root, 'docs', 'nested')).result)! as DirectoryNode;

      final operation = editor.copy([nodes['docs']!], inside);
      final messages = <String>[];
      operation.requests.listen((request) {
        messages.add(request.message);
        request.respond(OperationRequestOption.skip);
      });
      await operation.result;
      await pumpEventQueue();

      expect(messages.single, contains('into itself'));
      expect(await Directory(p.join(root, 'docs', 'nested', 'docs')).exists(), isFalse);
    });

    test('копирование в тот же каталог отклоняется', () async {
      final nodes = await listRoot();
      final sameDir = (await provider.resolvePath(root).result)! as DirectoryNode;

      final operation = editor.copy([nodes['notes.txt']!], sameDir);
      final messages = <String>[];
      operation.requests.listen((request) {
        messages.add(request.message);
        request.respond(OperationRequestOption.skip);
      });
      await operation.result;
      await pumpEventQueue();

      expect(messages.single, FsError(p.join(root, 'notes.txt'), FsErrorKind.alreadyExists).message);
    });

    test('ошибка на одном объекте не останавливает остальные', () async {
      final nodes = await listRoot();
      // Объект исчез уже после того, как каталог был прочитан.
      await File(p.join(root, 'notes.txt')).delete();

      final operation = editor.copy([nodes['notes.txt']!, nodes['report.txt']!], await targetDir());
      answerWith(operation, OperationRequestOption.skip);
      await operation.result;
      await pumpEventQueue();

      expect(await File(p.join(target, 'report.txt')).exists(), isTrue);
    });
  });
}
