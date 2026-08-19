import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip_archiver/fc_zip_archiver.dart';
import 'package:flex_commander/modules/local_fs/local_staging_area.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
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
      (host) => ZipTreeProvider.open(host, staging: const LocalStagingArea()),
      extensions: ZipTreeProvider.extensions,
    );
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<TreeProvider> mounted() async {
    final host = (await disk.resolvePath(archivePath).result)!;
    return registry.mount(ZipTreeProvider.schemeName, host);
  }

  Future<FsNode> onDisk(String path) async => (await disk.resolvePath(p.join(root, path)).result)!;

  Future<DirectoryNode> inArchive(TreeProvider zip, String path) async =>
      (await zip.resolvePath(path).result)! as DirectoryNode;

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

      await engine.copy([await onDisk('notes.txt')], await inArchive(zip, '/')).result;

      // Дерево показывает новую запись сразу.
      final names = (await zip.getDirectoryListing(await inArchive(zip, '/')).result).map((node) => node.name);
      expect(names, contains('notes.txt'));

      // И она же лежит в самом файле архива.
      expect(await archiveOnDisk(), containsPair('notes.txt', 'заметки'));
      // Прежние записи никуда не делись.
      expect(await archiveOnDisk(), containsPair('docs/guide.txt', 'руководство'));
    });

    test('каталог копируется со всем содержимым', () async {
      final zip = await mounted();

      await engine.copy([await onDisk('photos')], await inArchive(zip, '/')).result;

      expect(await archiveOnDisk(), containsPair('photos/cat.txt', 'кот'));
    });

    test('копирование во вложенный каталог архива', () async {
      final zip = await mounted();

      await engine.copy([await onDisk('notes.txt')], await inArchive(zip, '/docs')).result;

      expect(await archiveOnDisk(), containsPair('docs/notes.txt', 'заметки'));
      expect(await archiveOnDisk(), containsPair('docs/guide.txt', 'руководство'));
    });

    test('архив пересобирается один раз на всю работу', () async {
      final zip = await mounted() as WritableZipTreeProvider;
      final destination = await inArchive(zip, '/');

      // Границы работы движок сообщает сам: внутри них архив не трогается.
      await zip.beginWrites();
      await engine.copy([await onDisk('notes.txt')], destination).result;
      expect(await archiveOnDisk(), isNot(contains('notes.txt')), reason: 'внутри работы архив не пересобирается');

      await zip.endWrites();
      expect(await archiveOnDisk(), containsPair('notes.txt', 'заметки'));
    });

    test('содержимое читается обратно из архива', () async {
      final zip = await mounted();
      await engine.copy([await onDisk('notes.txt')], await inArchive(zip, '/')).result;

      final node = (await zip.resolvePath('/notes.txt').result)!;
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

      await engine.remove([(await zip.resolvePath('/readme.md').result)!], toTrash: false).result;

      expect(await archiveOnDisk(), isNot(contains('readme.md')));
      expect(await archiveOnDisk(), containsPair('docs/guide.txt', 'руководство'));
    });

    test('каталог удаляется со всем содержимым', () async {
      final zip = await mounted();

      await engine.remove([(await zip.resolvePath('/docs').result)!], toTrash: false).result;

      final left = await archiveOnDisk();
      expect(left.keys, isNot(contains('docs/guide.txt')));
      expect(left, containsPair('readme.md', 'привет'));
    });

    test('копирование поверх существующей записи заменяет её', () async {
      final zip = await mounted();
      await File(p.join(root, 'readme.md')).writeAsString('новая версия');

      // Перезапись — обычный вопрос движка. По умолчанию он предлагает
      // пропустить, поэтому в тесте отвечаем «перезаписать» явно.
      final operation = engine.copy([await onDisk('readme.md')], await inArchive(zip, '/'));
      operation.requests.listen((request) => request.respond(OperationOption.overwrite));
      await operation.result;

      expect(await archiveOnDisk(), containsPair('readme.md', 'новая версия'));
    });
  });

  group('архив внутри архива', () {
    test('открытый через временную копию остаётся только для чтения', () async {
      // Внешний архив с вложенным внутри.
      final inner = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.string('inside.txt', 'внутри')));
      final outerPath = p.join(root, 'outer.zip');
      await File(
        outerPath,
      ).writeAsBytes(ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.bytes('nested.zip', inner))));

      final outer = await registry.mount(ZipTreeProvider.schemeName, (await disk.resolvePath(outerPath).result)!);
      final nestedHost = (await outer.resolvePath('/nested.zip').result)!;
      final nested = await registry.mount(ZipTreeProvider.schemeName, nestedHost);

      // Писать в копию бессмысленно: изменения ушли бы вместе с ней.
      expect(nested.canWrite, isFalse);
      expect(nested.canReceive, isFalse);
      expect(outer.canWrite, isTrue);
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

      // Путь приёмника команда разбирает панелью — так же, как F5.
      final destination = (await panel.resolvePath('$archivePath:zip:/').result)! as DirectoryNode;
      await engine.copy([await onDisk('notes.txt')], destination).result;
      await panel.reload();

      expect(panel.nodes.map((node) => node.name), contains('notes.txt'));
    });
  });
}
