import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/local/local_tree_provider.dart';
import 'package:flex_commander/model/tree/provider_registry.dart';
import 'package:flex_commander/model/tree/transfer/transfer_engine.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flex_commander/model/tree/zip/zip_tree_provider.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Архив как источник дерева: на настоящем zip во временном каталоге.
void main() {
  late Directory temp;
  late String root;
  late String archivePath;
  late LocalTreeProvider disk;
  late ProviderRegistry registry;

  /// Собирает архив: два каталога, из которых один отдельной записью не
  /// записан вовсе — так делают почти все упаковщики.
  Future<void> writeArchive({bool broken = false}) async {
    final archive =
        Archive()
          ..add(ArchiveFile.string('readme.md', 'привет'))
          ..add(ArchiveFile.directory('docs/'))
          ..add(ArchiveFile.string('docs/guide.txt', 'руководство'))
          ..add(ArchiveFile.string('docs/deep/note.txt', 'глубоко'));

    final bytes = ZipEncoder().encodeBytes(archive);
    await File(archivePath).writeAsBytes(broken ? bytes.sublist(0, bytes.length ~/ 2) : bytes);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_zip');
    root = await temp.resolveSymbolicLinks();
    archivePath = p.join(root, 'sample.zip');
    await writeArchive();

    disk = LocalTreeProvider(homePath: root, readInIsolate: false);
    registry = ProviderRegistry(root: disk)
      ..register(ZipTreeProvider.schemeName, ZipTreeProvider.open, extensions: ZipTreeProvider.extensions);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<FsNode> hostNode() async => (await disk.resolvePath(archivePath).result)!;

  Future<TreeProvider> mounted() async => registry.mount(ZipTreeProvider.schemeName, await hostNode());

  Future<List<String>> namesIn(TreeProvider provider, String path) async {
    final dir = (await provider.resolvePath(path).result)! as DirectoryNode;
    final nodes = await provider.getDirectoryListing(dir).result;
    return nodes.map((node) => node.name).toList();
  }

  group('дерево архива', () {
    test('корень показывает содержимое верхнего уровня', () async {
      final zip = await mounted();

      // «..» ведёт наружу, туда, где лежит сам архив.
      expect(await namesIn(zip, '/'), ['..', 'docs', 'readme.md']);
    });

    test('каталог достраивается, даже если записи о нём в архиве нет', () async {
      final zip = await mounted();

      // `docs/deep/` отдельной записью не записан — он есть только в пути.
      expect(await namesIn(zip, '/docs'), ['..', 'deep', 'guide.txt']);
      expect(await namesIn(zip, '/docs/deep'), ['..', 'note.txt']);
    });

    test('у файла известны размер и дата', () async {
      final zip = await mounted();
      final node = (await zip.resolvePath('/readme.md').result)!;

      expect(node.size, utf8.encode('привет').length);
      expect((node as FileNode).modified, isNotNull);
    });

    test('несуществующего пути нет', () async {
      final zip = await mounted();

      expect(await zip.resolvePath('/docs/missing.txt').result, isNull);
    });

    test('размер задания считается по оглавлению', () async {
      final zip = await mounted();
      final docs = (await zip.resolvePath('/docs').result)!;

      final size = await zip.calculateSize([docs]).result;
      expect(size, utf8.encode('руководство').length + utf8.encode('глубоко').length);
    });
  });

  group('умения', () {
    test('архив читается, но не меняется', () async {
      final zip = await mounted();

      expect(zip.canWrite, isFalse);
      // Отдавать содержимое умеет, принимать — нет.
      expect(zip.canStream, isTrue);
      expect(zip.canReceive, isFalse);
    });

    test('настоящих путей у архива нет', () async {
      final zip = await mounted();

      // Отдать такой путь внешней программе нельзя: файла по нему не существует.
      expect(zip.capabilities.realFileSystem, isFalse);
      expect(zip.capabilities.canRename, isFalse);
      expect(zip.capabilities.canSeek, isFalse);
    });
  });

  group('содержимое', () {
    test('файл читается целиком', () async {
      final zip = await mounted() as ZipTreeProvider;
      final node = (await zip.resolvePath('/docs/guide.txt').result)!;

      final chunks = await (await zip.openRead(node)).toList();
      expect(utf8.decode([for (final chunk in chunks) ...chunk]), 'руководство');
    });

    test('offset пропускает начало', () async {
      final zip = await mounted() as ZipTreeProvider;
      final node = (await zip.resolvePath('/readme.md').result)!;

      final chunks = await (await zip.openRead(node, offset: 6)).toList();
      // «привет» в utf-8 — двенадцать байт, с шестого остаются три буквы.
      expect(utf8.decode([for (final chunk in chunks) ...chunk]), 'вет');
    });

    test('каталог содержимого не отдаёт', () async {
      final zip = await mounted() as ZipTreeProvider;
      final docs = (await zip.resolvePath('/docs').result)!;

      await expectLater(zip.openRead(docs), throwsA(isA<FsError>()));
    });
  });

  group('когда открыть нельзя', () {
    test('битый архив — отказ, а не пустое дерево', () async {
      await writeArchive(broken: true);

      await expectLater(mounted(), throwsA(isA<FsError>()));
    });

    test('архив без настоящего пути пока не открывается', () async {
      // Архив внутри архива или на сервере: оглавление лежит в конце файла,
      // и прочитать его, не умея прыгать по файлу, нельзя — нужен мост (5.7).
      final memory = InMemoryArchiveProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/inner.zip', content: [1, 2, 3]),
      ]);
      final host = (await memory.resolvePath('/home/inner.zip').result)!;

      await expectLater(
        ZipTreeProvider.open(host),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notSupported)),
      );
    });
  });

  group('когда открыть нельзя (продолжение)', () {
    test('не-архив с расширением zip не открывается пустым', () async {
      // Декодер объявляет мусор пустым архивом; пустая панель вместо ошибки —
      // худшее, чем может кончиться открытие.
      await File(archivePath).writeAsString('это вообще не архив');

      await expectLater(mounted(), throwsA(isA<FsError>()));
    });

    test('пустой архив открывается пустым: это не ошибка', () async {
      await File(archivePath).writeAsBytes(ZipEncoder().encodeBytes(Archive()));

      final zip = await mounted();
      expect(await namesIn(zip, '/'), ['..']);
    });
  });

  group('панель в архиве', () {
    late PanelController panel;

    setUp(() async {
      panel = PanelController(provider: disk, registry: registry, settings: PanelSettings.defaults(root));
      addTearDown(panel.dispose);
      await panel.openPath(root);
    });

    test('Enter на архиве показывает его содержимое', () async {
      panel.setCursorToName('sample.zip');

      expect(await panel.enterCurrent(), isNull);

      expect(panel.nodes.map((node) => node.name), containsAll(['docs', 'readme.md']));
      expect(panel.provider, isA<ZipTreeProvider>());
      // Внутри архива менять нечем — файловые команды выключатся сами.
      expect(panel.editor, isNull);
    });

    test('путь показывает цепочку, а «..» выводит наружу', () async {
      panel.setCursorToName('sample.zip');
      await panel.enterCurrent();
      panel.setCursorToName('docs');
      await panel.enterCurrent();

      // Машине — со схемой: этот путь сохраняется и разбирается обратно.
      expect(panel.directory?.pathString, '$archivePath:zip:/docs');
      // Пользователю — без неё: в архив входят как в каталог.
      expect(panel.directory?.displayPath, '$archivePath/docs');

      await panel.goUp();
      await panel.goUp();

      expect(panel.directory?.pathString, root);
      expect(panel.currentNode?.name, 'sample.zip');
      expect(panel.provider, same(disk));
    });

    test('сохранённый путь внутри архива открывается снова', () async {
      panel.setCursorToName('sample.zip');
      await panel.enterCurrent();
      panel.setCursorToName('docs');
      await panel.enterCurrent();

      final saved = panel.settings.path;
      final restored = PanelController(provider: disk, registry: registry, settings: PanelSettings.defaults(saved));
      addTearDown(restored.dispose);

      expect(await restored.openPath(saved), isTrue);
      expect(restored.nodes.map((node) => node.name), contains('guide.txt'));
    });
  });

  group('жизненный цикл', () {
    test('архив открыт, пока им пользуются, и закрывается по dispose', () async {
      final zip = await mounted() as ZipTreeProvider;
      final node = (await zip.resolvePath('/readme.md').result)!;

      // Читаем дважды: второй раз оглавление уже не перечитывается.
      expect(await (await zip.openRead(node)).toList(), isNotEmpty);
      expect(await (await zip.openRead(node)).toList(), isNotEmpty);

      await zip.dispose();

      // После закрытия узлами пользоваться нельзя, и провайдер это говорит.
      await expectLater(
        zip.openRead(node),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notSupported)),
      );
    });

    test('закрытый архив можно закрыть ещё раз', () async {
      final zip = await mounted() as ZipTreeProvider;

      await zip.dispose();
      await zip.dispose();
    });

    test('дерево читается и без единого чтения содержимого', () async {
      // В архив часто заходят посмотреть: открывать файл ради этого незачем.
      final zip = await mounted() as ZipTreeProvider;

      expect(await namesIn(zip, '/'), contains('readme.md'));

      await zip.dispose();
    });

    test('файл архива отпускается: его можно удалить', () async {
      final zip = await mounted() as ZipTreeProvider;
      final node = (await zip.resolvePath('/readme.md').result)!;
      await (await zip.openRead(node)).toList();

      await zip.dispose();
      await File(archivePath).delete();

      expect(await File(archivePath).exists(), isFalse);
    });
  });

  group('в цепочке провайдеров', () {
    test('архив открывается по расширению имени', () async {
      expect(registry.schemeFor(await hostNode()), ZipTreeProvider.schemeName);
    });

    test('путь внутрь архива разбирается целиком', () async {
      final node = await registry.resolvePath('$archivePath:zip:/docs/guide.txt').result;

      expect(node?.name, 'guide.txt');
      expect(node?.pathString, '$archivePath:zip:/docs/guide.txt');
    });

    test('файл из архива копируется на диск потоком', () async {
      final zip = await mounted();
      final source = (await zip.resolvePath('/docs/guide.txt').result)!;
      final target = (await disk.resolvePath(root).result)! as DirectoryNode;

      await const TreeTransferEngine().copy([source], target).result;

      expect(await File(p.join(root, 'guide.txt')).readAsString(), 'руководство');
    });

    test('каталог из архива копируется со всем содержимым', () async {
      final zip = await mounted();
      final source = (await zip.resolvePath('/docs').result)!;
      final target = (await disk.resolvePath(root).result)! as DirectoryNode;

      await const TreeTransferEngine().copy([source], target).result;

      expect(await File(p.join(root, 'docs', 'guide.txt')).readAsString(), 'руководство');
      expect(await File(p.join(root, 'docs', 'deep', 'note.txt')).readAsString(), 'глубоко');
    });
  });
}
