import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Копирование **в** архив: zip — контейнер, и добавить в него запись значит
/// пересобрать его целиком. Проверяется и то, что видно в дереве сразу, и то,
/// что осталось в файле на диске.
void main() {
  late Directory temp;
  late String root;
  late String archivePath;
  late LocalTreeProvider disk;
  late ProviderRegistry registry;
  const engine = TreeTransferEngine();

  Future<void> writeArchive() async {
    final archive =
        Archive()
          ..add(ArchiveFile.string('readme.md', 'привет'))
          ..add(ArchiveFile.directory('docs/'))
          ..add(ArchiveFile.string('docs/guide.txt', 'руководство'));

    await File(archivePath).writeAsBytes(ZipEncoder().encodeBytes(archive));
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_zip_write');
    root = await temp.resolveSymbolicLinks();
    archivePath = p.join(root, 'sample.zip');
    await writeArchive();

    await File(p.join(root, 'notes.txt')).writeAsString('заметки');
    await Directory(p.join(root, 'photos')).create();
    await File(p.join(root, 'photos', 'cat.txt')).writeAsString('кот');

    disk = LocalTreeProvider(homePath: root, readInIsolate: false);
    registry = ProviderRegistry(root: disk)..register(
      ZipTreeProvider.schemeName,
      () => TaskOperation<FsNode, TreeProvider>(
        (op, host) => ZipTreeProvider.open(host, credentials: FakeCredentials(), staging: const LocalStagingArea()),
      ),
      extensions: ZipTreeProvider.extensions,
    );
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<TreeProvider> mounted() async {
    final host = (await disk.resolvePath().run(archivePath))!;
    return (await registry.acquire().run(AcquireParams(ZipTreeProvider.schemeName, host))).provider;
  }

  Future<FsNode> onDisk(String path) async => (await disk.resolvePath().run(p.join(root, path)))!;

  Future<DirectoryNode> inArchive(TreeProvider zip, String path) async =>
      (await zip.resolvePath().run(path))! as DirectoryNode;

  /// Что лежит в файле архива — прочитанное заново, а не из памяти провайдера.
  Future<Map<String, String>> archiveOnDisk() async {
    final archive = ZipDecoder().decodeBytes(await File(archivePath).readAsBytes());
    return {
      for (final file in archive.files)
        if (file.isFile) file.name: utf8.decode(file.readBytes() ?? []),
    };
  }

  group('копирование в архив', () {
    test('файл с диска оказывается в архиве', () async {
      final zip = await mounted();

      await engine.copy().run(TransferParams([await onDisk('notes.txt')], await inArchive(zip, '/')));

      // Дерево показывает новую запись сразу.
      final names = (await zip.getDirectoryListing().run(
        ListingParams(await inArchive(zip, '/')),
      )).map((node) => node.name);
      expect(names, contains('notes.txt'));

      // И она же лежит в самом файле архива.
      expect(await archiveOnDisk(), containsPair('notes.txt', 'заметки'));
      // Прежние записи никуда не делись.
      expect(await archiveOnDisk(), containsPair('docs/guide.txt', 'руководство'));
    });

    test('каталог копируется со всем содержимым', () async {
      final zip = await mounted();

      await engine.copy().run(TransferParams([await onDisk('photos')], await inArchive(zip, '/')));

      expect(await archiveOnDisk(), containsPair('photos/cat.txt', 'кот'));
    });

    test('копирование во вложенный каталог архива', () async {
      final zip = await mounted();

      await engine.copy().run(TransferParams([await onDisk('notes.txt')], await inArchive(zip, '/docs')));

      expect(await archiveOnDisk(), containsPair('docs/notes.txt', 'заметки'));
      expect(await archiveOnDisk(), containsPair('docs/guide.txt', 'руководство'));
    });

    test('архив пересобирается один раз на всю работу', () async {
      final zip = await mounted() as WritableZipTreeProvider;
      final destination = await inArchive(zip, '/');

      // Границы работы движок сообщает сам: внутри них архив не трогается.
      await zip.beginWrites(FakeOperationContext());
      await engine.copy().run(TransferParams([await onDisk('notes.txt')], destination));
      expect(await archiveOnDisk(), isNot(contains('notes.txt')), reason: 'внутри работы архив не пересобирается');

      await zip.endWrites(FakeOperationContext());
      expect(await archiveOnDisk(), containsPair('notes.txt', 'заметки'));
    });

    test('содержимое читается обратно из архива', () async {
      final zip = await mounted();
      await engine.copy().run(TransferParams([await onDisk('notes.txt')], await inArchive(zip, '/')));

      final node = (await zip.resolvePath().run('/notes.txt'))!;
      final bytes = await (await (zip as FileContentProvider).openRead(node)).expand((chunk) => chunk).toList();

      expect(utf8.decode(bytes), 'заметки');
    });
  });

  group('изменение архива', () {
    test('каталог создаётся прямо в архиве', () async {
      final zip = await mounted() as NodeEditor;

      await zip.createDirectory(await inArchive(zip as TreeProvider, '/'), 'new');

      final archive = ZipDecoder().decodeBytes(await File(archivePath).readAsBytes());
      expect(archive.files.map((file) => file.name), contains('new/'));
    });

    test('запись удаляется из архива', () async {
      final zip = await mounted();

      await engine.remove().run(RemoveParams([(await zip.resolvePath().run('/readme.md'))!], toTrash: false));

      expect(await archiveOnDisk(), isNot(contains('readme.md')));
      expect(await archiveOnDisk(), containsPair('docs/guide.txt', 'руководство'));
    });

    test('каталог удаляется со всем содержимым', () async {
      final zip = await mounted();

      await engine.remove().run(RemoveParams([(await zip.resolvePath().run('/docs'))!], toTrash: false));

      final left = await archiveOnDisk();
      expect(left.keys, isNot(contains('docs/guide.txt')));
      expect(left, containsPair('readme.md', 'привет'));
    });

    test('копирование поверх существующей записи заменяет её', () async {
      final zip = await mounted();
      await File(p.join(root, 'readme.md')).writeAsString('новая версия');

      // Перезапись — обычный вопрос движка. По умолчанию он предлагает
      // пропустить, поэтому в тесте отвечаем «перезаписать» явно.
      final operation = engine.copy();
      operation.requests.listen((request) => request.respond(TransferAnswers.overwrite));
      operation.start(TransferParams([await onDisk('readme.md')], await inArchive(zip, '/')));
      await operation.result;

      expect(await archiveOnDisk(), containsPair('readme.md', 'новая версия'));
    });
  });

  group('о цене предупреждают заранее', () {
    test('копирование в архив спрашивает — и отказ ничего не меняет', () async {
      final zip = await mounted();
      final before = await archiveOnDisk();

      final questions = <String>[];
      final operation = engine.copy();
      operation.requests.listen((request) {
        questions.add(request.message);
        request.respond(TransferAnswers.cancel);
      });
      operation.start(TransferParams([await onDisk('notes.txt')], await inArchive(zip, '/')));
      await operation.result.then((_) => null, onError: (_) => null);

      // Вопрос задаётся **до** работы: дописать запись в zip нельзя, архив
      // пересобирается целиком, и знать об этом человек должен заранее.
      expect(questions.single, contains('repacks the whole archive'));
      expect(await archiveOnDisk(), before, reason: 'отказ означает, что работы не было вовсе');
    });

    test('согласие делает работу', () async {
      final zip = await mounted();

      final operation = engine.copy();
      operation.requests.listen((request) => request.respond(TransferAnswers.proceed));
      operation.start(TransferParams([await onDisk('notes.txt')], await inArchive(zip, '/')));
      await operation.result;

      expect(await archiveOnDisk(), containsPair('notes.txt', 'заметки'));
    });
  });

  group('архив внутри архива', () {
    test('остаётся читающим: внешний архив не умеет заменить его одним действием', () async {
      // Внешний архив с вложенным внутри.
      final inner = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.string('inside.txt', 'внутри')));
      final outerPath = p.join(root, 'outer.zip');
      await File(
        outerPath,
      ).writeAsBytes(ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.bytes('nested.zip', inner))));

      final outerHost = (await disk.resolvePath().run(outerPath))!;
      final outer = (await registry.acquire().run(AcquireParams(ZipTreeProvider.schemeName, outerHost))).provider;
      final nestedHost = (await outer.resolvePath().run('/nested.zip'))!;
      final nested = (await registry.acquire().run(AcquireParams(ZipTreeProvider.schemeName, nestedHost))).provider;

      // Вернуть копию хозяину можно только заменой **одним действием**, то
      // есть переименованием, — а zip переименовывать не умеет вовсе. Значит
      // обрыв на середине оставил бы вместо архива обрубок, и такой архив
      // остаётся читающим, как и был.
      expect(outer.canWrite, isTrue);
      expect(outer.capabilities.canRename, isFalse);
      expect(nested.canWrite, isFalse);
      expect(nested.canReceive, isFalse);
    });
  });

  group('архив не на диске', () {
    test('пишется и уезжает обратно хозяину', () async {
      // Источник, ведущий себя как сервер: настоящих путей нет, а принять файл
      // и переименовать умеет. Ровно на таком архив и был read-only.
      final server = InMemoryContentProvider([FakeEntry.directory('/srv')])..home = '/srv';
      server.capabilities = const ProviderCapabilities(canRename: true, maxConcurrency: 1);
      final bytes = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.string('inside.txt', 'внутри')));
      server.add(FakeEntry.file('/srv/remote.zip', content: bytes));

      final remotes = ProviderRegistry(root: server)..register(
        ZipTreeProvider.schemeName,
        () => TaskOperation<FsNode, TreeProvider>(
          (op, host) => ZipTreeProvider.open(host, credentials: FakeCredentials(), staging: const LocalStagingArea()),
        ),
        extensions: ZipTreeProvider.extensions,
      );

      final host = (await server.resolvePath().run('/srv/remote.zip'))!;
      final archive = (await remotes.acquire().run(AcquireParams(ZipTreeProvider.schemeName, host))).provider;

      // Копию есть кому вернуть — значит в архив можно писать.
      expect(archive.canWrite, isTrue);

      final operation = engine.copy();
      operation.start(
        TransferParams([
          (await disk.resolvePath().run(p.join(root, 'notes.txt')))!,
        ], (await archive.resolvePath().run('/'))! as DirectoryNode),
      );
      await operation.result;

      // На «сервере» лежит уже пересобранный архив — с прежней записью и новой.
      final updated = server.entryAt('/srv/remote.zip')!.content;
      final entries = ZipDecoder().decodeBytes(Uint8List.fromList(updated));
      expect(entries.files.map((file) => file.name), containsAll(<String>['inside.txt', 'notes.txt']));
      // И ничего лишнего рядом: временное имя убрано переименованием.
      expect(server.entryAt('/srv/.remote.zip.fc-part'), isNull);
    });
  });

  group('панель с открытым архивом', () {
    test('видит скопированное в неё сразу после работы', () async {
      // Как в приложении: панель стоит в архиве, копируют в неё же.
      final panel = testPanel(provider: disk, registry: registry, settings: PanelSettings.defaults(root));
      addTearDown(panel.dispose);
      await panel.openPath(root);

      panel.setCursorToName('sample.zip');
      await panel.enterCurrent();
      expect(panel.provider, isA<WritableZipTreeProvider>());

      // Путь приёмника команда разбирает панелью — так же, как F5, и держит
      // аренду всё время работы: панель за это время вправе уйти куда угодно.
      final destination = await panel.resolvePath().run('$archivePath:zip:/');
      try {
        await engine.copy().run(TransferParams([await onDisk('notes.txt')], destination.node! as DirectoryNode));
      } finally {
        await destination.release();
      }
      await panel.reload();

      expect(panel.nodes.map((node) => node.name), contains('notes.txt'));
      // Второго экземпляра поверх того же файла не завелось: панель и приёмник
      // — это один и тот же открытый архив.
      expect(destination.node!.provider, same(panel.provider));
    });
  });
}
