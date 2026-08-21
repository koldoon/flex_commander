import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:flex_commander/modules/local_fs/local_staging_area.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
    // Не 'flex_commander_zip': так называет свои каталоги сессия временных
    // копий, и тест ниже считает именно их.
    temp = await Directory.systemTemp.createTemp('fc_zip_fixture');
    root = await temp.resolveSymbolicLinks();
    archivePath = p.join(root, 'sample.zip');
    await writeArchive();

    disk = LocalTreeProvider(homePath: root, readInIsolate: false);
    registry = ProviderRegistry(root: disk)..register(
      ZipTreeProvider.schemeName,
      (host) => TaskOperation<TreeProvider>(
        (op) => ZipTreeProvider.open(host, credentials: FakeCredentials(), staging: const LocalStagingArea()),
      ),
      extensions: ZipTreeProvider.extensions,
    );
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<FsNode> hostNode() async => (await disk.resolvePath(archivePath).result)!;

  Future<TreeProvider> mounted() async =>
      (await registry.acquire(ZipTreeProvider.schemeName, await hostNode()).result).provider;

  /// Узел из разбора пути; аренду тест отпускает сам — в приложении её держит
  /// тот, кто путь и просил разобрать.
  Future<FsNode?> nodeOf(AsyncOperation<ResolvedNode> operation) async => (await operation.result).node;

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
    test('архив на диске и читается, и принимает содержимое', () async {
      final zip = await mounted();

      // Писать в архив можно: он пересобирается целиком, но снаружи это
      // обычный приёмник.
      expect(zip.canWrite, isTrue);
      expect(zip.canStream, isTrue);
      expect(zip.canReceive, isTrue);
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

    test('источник без настоящих путей и без байтов открыть нечем', () async {
      // Дерево есть, содержимого нет: ни прочитать оглавление, ни скопировать.
      final memory = InMemoryReadOnlyProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/inner.zip', content: [1, 2, 3]),
      ]);
      final host = (await memory.resolvePath('/home/inner.zip').result)!;

      await expectLater(
        ZipTreeProvider.open(host, credentials: FakeCredentials(), staging: const LocalStagingArea()),
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
      panel = testPanel(provider: disk, registry: registry, settings: PanelSettings.defaults(root));
      addTearDown(panel.dispose);
      await panel.openPath(root);
    });

    test('Enter на архиве показывает его содержимое', () async {
      panel.setCursorToName('sample.zip');

      expect(await panel.enterCurrent(), isNull);

      expect(panel.nodes.map((node) => node.name), containsAll(['docs', 'readme.md']));
      expect(panel.provider, isA<ZipTreeProvider>());
      // В архив на диске можно писать: файловые команды остаются доступными.
      expect(panel.editor, isNotNull);
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
      final restored = testPanel(provider: disk, registry: registry, settings: PanelSettings.defaults(saved));
      addTearDown(restored.dispose);

      expect(await restored.openPath(saved), isTrue);
      expect(restored.nodes.map((node) => node.name), contains('guide.txt'));
    });

    test('круг замкнулся: показанный путь открывается обратно', () async {
      panel.setCursorToName('sample.zip');
      await panel.enterCurrent();
      panel.setCursorToName('docs');
      await panel.enterCurrent();

      // То, что человек видит в заголовке и правит в окне `Cmd-F1`. Схемы
      // архива в нём нет, и разобрать его можно только спросив источник о типе
      // каждого звена.
      final shown = panel.directory!.displayPath;
      expect(shown, '$archivePath/docs');

      expect(await panel.openPath(shown), isTrue);
      expect(panel.directory?.displayPath, shown);
      expect(panel.nodes.map((node) => node.name), contains('guide.txt'));
    });

    test('и корень архива тоже — иначе круг рвался бы на нём', () async {
      panel.setCursorToName('sample.zip');
      await panel.enterCurrent();

      final shown = panel.directory!.displayPath;
      expect(shown, archivePath);

      // Строка кончается файлом архива, а панель ждёт каталог: вход в него —
      // то же самое, что Enter.
      expect(await panel.openPath(shown), isTrue);
      expect(panel.provider, isA<ZipTreeProvider>());
      expect(panel.nodes.map((node) => node.name), containsAll(['docs', 'readme.md']));
    });
  });

  group('архив не в локальной ФС', () {
    /// Архив, лежащий в чужом источнике: у него нет настоящего пути, и
    /// прочитать его оглавление можно только через временную копию.
    Future<FsNode> hostedInMemory() async {
      final memory = InMemoryArchiveProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/inner.zip', content: await File(archivePath).readAsBytes()),
      ]);
      return (await memory.resolvePath('/home/inner.zip').result)!;
    }

    test('открывается через временную копию', () async {
      final zip = await ZipTreeProvider.open(
        await hostedInMemory(),
        credentials: FakeCredentials(),
        staging: const LocalStagingArea(),
      );

      expect(await namesIn(zip, '/'), containsAll(['docs', 'readme.md']));

      await (zip as ProviderLifecycle).dispose();
    });

    test('содержимое читается из копии', () async {
      final zip =
          await ZipTreeProvider.open(
                await hostedInMemory(),
                credentials: FakeCredentials(),
                staging: const LocalStagingArea(),
              )
              as ZipTreeProvider;
      final node = (await zip.resolvePath('/docs/guide.txt').result)!;

      final chunks = await (await zip.openRead(node)).toList();
      expect(utf8.decode([for (final chunk in chunks) ...chunk]), 'руководство');

      await zip.dispose();
    });

    test('копия убирается вместе с провайдером', () async {
      final zip =
          await ZipTreeProvider.open(
                await hostedInMemory(),
                credentials: FakeCredentials(),
                staging: const LocalStagingArea(),
              )
              as ZipTreeProvider;
      final copy = zip.archivePath;
      expect(await File(copy).exists(), isTrue);
      // Копия лежит не там, где оригинал: это временный файл.
      expect(copy, isNot(archivePath));

      await zip.dispose();

      expect(await File(copy).exists(), isFalse);
      expect(await Directory(p.dirname(copy)).exists(), isFalse);
    });

    test('копия не переживает неудачного открытия', () async {
      // Временные каталоги считаются в своём месте, а не в общем каталоге
      // системы: туда же складывают своё и остальные работы, и по нему ничего
      // не проверишь.
      final staging = LocalStagingArea(root: temp);
      int sessions() =>
          temp.listSync().where((entity) => p.basename(entity.path).startsWith('flex_commander_zip_')).length;

      final broken = InMemoryArchiveProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/inner.zip', content: utf8.encode('это вообще не архив')),
      ]);
      final host = (await broken.resolvePath('/home/inner.zip').result)!;
      final before = sessions();

      await expectLater(
        ZipTreeProvider.open(host, credentials: FakeCredentials(), staging: staging),
        throwsA(isA<FsError>()),
      );

      // Копию успели сделать, а архив не открылся — за собой убрано.
      expect(sessions(), before);
    });

    test('локальный архив не копируется вовсе', () async {
      final zip = await mounted() as ZipTreeProvider;

      // Настоящий путь есть — копировать нечего: ровно за этим и заведён
      // realFileSystem.
      expect(zip.archivePath, archivePath);

      await zip.dispose();
      expect(await File(archivePath).exists(), isTrue);
    });
  });

  group('архив внутри архива', () {
    late String outerPath;

    setUp(() async {
      // Внешний архив, внутри которого лежит наш sample.zip целиком.
      outerPath = p.join(root, 'outer.zip');
      final outer =
          Archive()
            ..add(ArchiveFile.bytes('nested/sample.zip', await File(archivePath).readAsBytes()))
            ..add(ArchiveFile.string('note.txt', 'снаружи'));
      await File(outerPath).writeAsBytes(ZipEncoder().encodeBytes(outer));
    });

    test('открывается и читается насквозь', () async {
      final node = await nodeOf(registry.resolvePath('$outerPath:zip:/nested/sample.zip:zip:/docs/guide.txt'));

      expect(node, isNotNull);
      expect(node!.name, 'guide.txt');
      // Путь пользователю — без схем, как у обычных каталогов.
      expect(node.displayPath, '$outerPath/nested/sample.zip/docs/guide.txt');

      final inner = node.provider as ZipTreeProvider;
      final chunks = await (await inner.openRead(node)).toList();
      expect(utf8.decode([for (final chunk in chunks) ...chunk]), 'руководство');
    });

    test('панель проходит вглубь и возвращается, закрывая за собой', () async {
      final panel = testPanel(provider: disk, registry: registry, settings: PanelSettings.defaults(root));
      addTearDown(panel.dispose);
      await panel.openPath(root);

      panel.setCursorToName('outer.zip');
      await panel.enterCurrent();
      panel.setCursorToName('nested');
      await panel.enterCurrent();
      panel.setCursorToName('sample.zip');
      await panel.enterCurrent();

      // Два архива в стопке; внутренний живёт временной копией внешнего.
      final inner = panel.provider as ZipTreeProvider;
      expect(inner.archivePath, isNot(outerPath));
      expect(await File(inner.archivePath).exists(), isTrue);
      expect(panel.directory?.displayPath, '$outerPath/nested/sample.zip');

      // Наружу одним прыжком: закрыться должны оба.
      expect(await panel.openPath(root), isTrue);
      // Закрытие асинхронное: панель не ждёт его, чтобы показать каталог.
      await pumpEventQueue();

      expect(panel.provider, same(disk));
      expect(await File(inner.archivePath).exists(), isFalse);
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
      final node = await nodeOf(registry.resolvePath('$archivePath:zip:/docs/guide.txt'));

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
