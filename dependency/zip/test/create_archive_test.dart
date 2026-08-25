import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Упаковка выбранного в новый архив: команда `Shift-F5`.
///
/// Приложение собирается по-настоящему — с модулем архива и настоящим диском:
/// упаковщику нужен файл, по которому можно ходить.
void main() {
  late Directory temp;
  late String root;
  late String source;
  late String target;
  late AppRuntime runtime;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    temp = await Directory.systemTemp.createTemp('fc_zip_create');
    root = await temp.resolveSymbolicLinks();
    source = p.join(root, 'source');
    target = p.join(root, 'target');
    await Directory(source).create();
    await Directory(target).create();

    await File(p.join(source, 'notes.txt')).writeAsString('заметки');
    await Directory(p.join(source, 'docs')).create();
    await File(p.join(source, 'docs', 'guide.txt')).writeAsString('руководство');
    await Directory(p.join(source, 'docs', 'empty')).create();

    runtime = await testApp(
      provider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: [const ZipArchiver()],
      settings: AppSettings(left: PanelSettings.defaults(source), right: PanelSettings.defaults(target)),
    );
    await runtime.app.start();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Что лежит в созданном архиве: имя записи → содержимое (null у каталогов).
  Future<Map<String, String?>> archiveAt(String name) async {
    final archive = ZipDecoder().decodeBytes(await File(p.join(target, name)).readAsBytes());
    return {for (final file in archive.files) file.name: file.isFile ? utf8.decode(file.readBytes() ?? []) : null};
  }

  /// Запускает упаковку с заданным именем — как это делает окно команды.
  Future<AppCommand> pack({String name = 'archive', ZipCompression? compression, bool followLinks = false}) async {
    final command =
        runtime.commands.create(CreateZipArchiveCommand.commandId)!
          ..setParam(CreateZipArchiveCommand.nameParam, name)
          ..setParam(CreateZipArchiveCommand.compressionParam, (compression ?? ZipCompression.normal).name)
          ..setParam(CreateZipArchiveCommand.followLinksParam, followLinks);
    await command.execute();
    return command;
  }

  group('символические ссылки', () {
    setUp(() async {
      // Ссылка на каталог: узел у неё не `DirectoryNode`, и поток по ней не
      // открыть. На этом упаковка каталога с `.framework` внутри и падала.
      await Link(p.join(source, 'docs', 'shortcut')).create(p.join(source, 'docs', 'empty'));
    });

    // Окна в этих тестах нет, поэтому на вопрос о ссылке берётся ответ по
    // умолчанию — «пропустить» (см. `AsyncCommandBase`). Сам вопрос и ответы
    // на него проверяются на движке переноса.

    test('ссылка на каталог не роняет упаковку', () async {
      runtime.app.left.setCursorToName('docs');

      final command = await pack(name: 'docs.zip');

      expect(command.error, isNull);
      // Остальное упаковалось: одна ссылка не должна стоить всей работы.
      expect((await archiveAt('docs.zip')).keys, contains('docs/guide.txt'));
    });

    test('не следуем — ссылка в архив не попадает', () async {
      runtime.app.left.setCursorToName('docs');

      await pack(name: 'docs.zip');

      // Хранить ссылку в zip нам нечем (см. комментарий в команде), а
      // подменять её содержимым цели молча нельзя.
      expect((await archiveAt('docs.zip')).keys, isNot(contains('docs/shortcut')));
      expect((await archiveAt('docs.zip')).keys, isNot(contains('docs/shortcut/')));
    });

    test('следуем — в архив ложится содержимое цели', () async {
      await File(p.join(source, 'docs', 'empty', 'inside.txt')).writeAsString('внутри');
      runtime.app.left.setCursorToName('docs');

      await pack(name: 'docs.zip', followLinks: true);

      expect(await archiveAt('docs.zip'), containsPair('docs/shortcut/inside.txt', 'внутри'));
    });

    test('ссылка на саму упаковываемую ветку не уводит в бесконечность', () async {
      // `docs/loop → docs`: пойти по ней — значит паковать себя в себя.
      await Link(p.join(source, 'docs', 'loop')).create(p.join(source, 'docs'));
      runtime.app.left.setCursorToName('docs');

      final command = await pack(name: 'docs.zip', followLinks: true);

      expect(command.error, isNull);
      expect((await archiveAt('docs.zip')).keys, contains('docs/guide.txt'));
    });
  });

  group('упаковка', () {
    test('файл под курсором уходит в новый архив', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'notes');

      // Расширение дописывается само: команда называется «create zip archive».
      expect(await archiveAt('notes.zip'), containsPair('notes.txt', 'заметки'));
    });

    test('каталог пакуется со всем содержимым, включая пустой', () async {
      runtime.app.left.setCursorToName('docs');

      await pack(name: 'docs.zip');

      final entries = await archiveAt('docs.zip');
      expect(entries, containsPair('docs/guide.txt', 'руководство'));
      // Пустой каталог существует в архиве только записью — без неё он пропал бы.
      expect(entries.keys, contains('docs/empty/'));
    });

    test('пакуется всё помеченное, а не только объект под курсором', () async {
      runtime.app.left
        ..setCursorToName('notes.txt')
        ..toggleCurrentMark()
        ..setCursorToName('docs')
        ..toggleCurrentMark();

      await pack(name: 'both');

      final entries = await archiveAt('both.zip');
      expect(entries, containsPair('notes.txt', 'заметки'));
      expect(entries, containsPair('docs/guide.txt', 'руководство'));
    });

    test('архив ложится в каталог пассивной панели', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'here');

      expect(File(p.join(target, 'here.zip')).existsSync(), isTrue);
      expect(File(p.join(source, 'here.zip')).existsSync(), isFalse);
    });

    test('панель-приёмник показывает новый архив сразу', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await pack(name: 'fresh');

      expect(runtime.app.right.nodes.map((node) => node.name), contains('fresh.zip'));
    });

    test('созданный архив открывается как дерево', () async {
      runtime.app.left.setCursorToName('docs');
      await pack(name: 'docs');

      runtime.app.right
        ..setCursorToName('docs.zip')
        ..pageSize = 20;
      await runtime.app.right.enterCurrent();

      expect(runtime.app.right.provider, isA<ZipTreeProvider>());
      expect(runtime.app.right.nodes.map((node) => node.name), containsAll(['..', 'docs']));
    });
  });

  group('степень сжатия', () {
    test('без сжатия архив заметно больше, чем при лучшем', () async {
      // Сжимаемое содержимое: на случайном шуме разницы не увидеть.
      await File(p.join(source, 'big.txt')).writeAsString('повторяющийся текст ' * 500);
      await runtime.app.left.reload();
      runtime.app.left.setCursorToName('big.txt');

      await pack(name: 'stored', compression: ZipCompression.none);
      await pack(name: 'packed', compression: ZipCompression.best);

      final stored = await File(p.join(target, 'stored.zip')).length();
      final packed = await File(p.join(target, 'packed.zip')).length();
      expect(packed, lessThan(stored));
    });

    test('по умолчанию — среднее сжатие', () {
      expect(ZipCompression.byName(null), ZipCompression.normal);
      expect(ZipCompression.byName('такого нет'), ZipCompression.normal);
      expect(ZipCompression.normal.level, 6);
    });
  });

  group('имя архива', () {
    test('занятое имя — ошибка, а не молчаливая перезапись', () async {
      await File(p.join(target, 'taken.zip')).writeAsString('чужое');
      runtime.app.left.setCursorToName('notes.txt');

      final command =
          runtime.commands.create(CreateZipArchiveCommand.commandId)!
            ..setParam(CreateZipArchiveCommand.nameParam, 'taken.zip');

      await expectLater(command.execute(), throwsA(isA<FsError>()));
      expect(await File(p.join(target, 'taken.zip')).readAsString(), 'чужое');
    });

    test('пустое имя не проходит', () async {
      runtime.app.left.setCursorToName('notes.txt');

      final command =
          runtime.commands.create(CreateZipArchiveCommand.commandId)!
            ..setParam(CreateZipArchiveCommand.nameParam, '   ');

      await expectLater(command.execute(), throwsA(isA<FsError>()));
    });
  });

  group('команда', () {
    test('закреплена за Shift-F5 и видна в списке команд', () {
      expect(runtime.commands.commandFor(KeyCombination.parse('Shift-F5'))?.id, CreateZipArchiveCommand.commandId);
      expect(runtime.commands.find(CreateZipArchiveCommand.commandId)?.label, 'Mk Zip');
    });

    test('рассказывает о ходе работы, как перенос', () {
      final command = runtime.commands.find(CreateZipArchiveCommand.commandId)!;

      expect(command.canRunInBackground, isTrue);
      expect(command.dialogTitle, 'Create ZIP archive');
    });
  });

  group('ход работы', () {
    test('учитываются оба плеча: и упаковка, и передача приёмнику', () async {
      await File(p.join(source, 'big.txt')).writeAsString('текст ' * 2000);
      await runtime.app.left.reload();
      runtime.app.left.setCursorToName('big.txt');
      final sourceSize = await File(p.join(source, 'big.txt')).length();

      final command = await pack(name: 'work') as AsyncCommandBase;

      // Работа кончилась целиком, а её объём — это прочитанные исходные байты
      // плюс отданные приёмнику: одного плеча мало.
      expect(command.bytes, command.totalBytes);
      expect(command.totalBytes, greaterThan(sourceSize));
      expect(command.progress, 1);
    });

    test('байты упаковки учитываются по мере обхода, а не одним скачком', () async {
      for (var i = 0; i < 3; i++) {
        await File(p.join(source, 'file$i.txt')).writeAsString('содержимое $i ' * 200);
      }
      await runtime.app.left.reload();
      runtime.app.left
        ..setCursorToName('file0.txt')
        ..toggleCurrentMark()
        ..setCursorToName('file1.txt')
        ..toggleCurrentMark()
        ..setCursorToName('file2.txt')
        ..toggleCurrentMark();

      final command = await pack(name: 'moving') as AsyncCommandBase;

      // Каждый упакованный файл — это его байты в общем счёте; на глаз это и
      // есть движение бара. Что показ ещё и не частит, решает throttle окна.
      expect(command.processed, greaterThanOrEqualTo(3));
      expect(command.bytes, command.totalBytes);
    });
  });
}
