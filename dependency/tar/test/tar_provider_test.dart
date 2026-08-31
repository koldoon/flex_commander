import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_tar/fc_tar.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Архивы tar, gz и tar.gz.
///
/// Архивы собираются **системным `tar`**, а не своими руками: проверять надо
/// то, что приходит из мира Unix, а не то, что мы сами же и записали. Иначе
/// сойдутся две одинаковые ошибки — в записи и в чтении.
void main() {
  late Directory work;
  late LocalTreeProvider local;
  late StagingArea staging;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('fc_tar_test');
    local = LocalTreeProvider();
    staging = LocalStagingArea(root: work);
  });

  tearDown(() async {
    await work.delete(recursive: true);
  });

  /// Дерево, которое пакуется во все архивы этого файла.
  Future<void> makeTree() async {
    final root = Directory(p.join(work.path, 'src'))..createSync();
    Directory(p.join(root.path, 'lib')).createSync();
    File(p.join(root.path, 'readme.md')).writeAsStringSync('# hello');
    File(p.join(root.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}');
    File(p.join(root.path, 'run.sh'))
      ..writeAsStringSync('#!/bin/sh\n')
      ..parent.path;
    Process.runSync('chmod', ['755', p.join(root.path, 'run.sh')]);
    Link(p.join(root.path, 'link.md')).createSync('readme.md');
  }

  /// Зовёт системный `tar` из каталога работы.
  Future<String> pack(List<String> arguments, String name) async {
    final result = await Process.run('tar', arguments, workingDirectory: work.path);
    expect(result.exitCode, 0, reason: 'tar: ${result.stderr}');
    return p.join(work.path, name);
  }

  /// Узел локальной ФС по пути — то, над чем монтируется провайдер архива.
  Future<FsNode> nodeAt(String path) async {
    final node = await local.resolvePath().run(path);
    expect(node, isNotNull, reason: 'нет файла $path');
    return node!;
  }

  Future<TreeProvider> openTar(String path) async => TarTreeProvider.open(await nodeAt(path), staging: staging);

  Future<List<String>> namesIn(TreeProvider provider, String path) async {
    final dir = (await provider.resolvePath().run(path))! as DirectoryNode;
    final nodes = await provider.getDirectoryListing().run(ListingParams(dir, includeHidden: true));
    return [for (final node in nodes) node.name]..remove('..');
  }

  Future<String> readText(TreeProvider provider, FsNode node) async {
    final chunks = await (provider as FileContentProvider).openRead(node);
    return utf8.decode(await chunks.expand((chunk) => chunk).toList());
  }

  group('tar', () {
    test('дерево видно целиком: каталоги, файлы и размеры', () async {
      await makeTree();
      final path = await pack(['-cf', 'src.tar', 'src'], 'src.tar');

      final provider = await openTar(path);

      expect(await namesIn(provider, '/'), ['src']);
      expect(await namesIn(provider, '/src'), containsAll(['lib', 'readme.md', 'run.sh']));

      final readme = (await provider.resolvePath().run('/src/readme.md'))!;
      expect(readme.size, '# hello'.length);
      expect(readme, isA<FileNode>());
    });

    test('содержимое читается по смещению, а не с начала архива', () async {
      await makeTree();
      final path = await pack(['-cf', 'src.tar', 'src'], 'src.tar');
      final provider = await openTar(path);

      final main = (await provider.resolvePath().run('/src/lib/main.dart'))!;
      expect(await readText(provider, main), 'void main() {}');

      // Смещение внутри записи — то, ради чего и заведён указатель.
      final rest = await (provider as FileContentProvider).openRead(main, offset: 5);
      expect(utf8.decode(await rest.expand((chunk) => chunk).toList()), 'main() {}');
    });

    test('права и ссылки сохраняются', () async {
      await makeTree();
      final path = await pack(['-cf', 'src.tar', 'src'], 'src.tar');
      final provider = await openTar(path);

      final script = (await provider.resolvePath().run('/src/run.sh'))! as FileNode;
      expect(script.attributes.isExecutable, isTrue, reason: 'права — главное отличие tar от zip');
      expect(script.executable, isTrue);

      final link = (await provider.resolvePath().run('/src/link.md'))!;
      expect(link, isA<LinkNode>());
      expect((link as LinkNode).reference, 'readme.md');
    });

    test('длинное имя из отдельной записи', () async {
      final deep = List.filled(12, 'очень-длинное-имя-каталога').join('/');
      Directory(p.join(work.path, deep)).createSync(recursive: true);
      File(p.join(work.path, deep, 'deep.txt')).writeAsStringSync('deep');
      final path = await pack(['-cf', 'long.tar', deep.split('/').first], 'long.tar');

      final provider = await openTar(path);
      final node = (await provider.resolvePath().run('/$deep/deep.txt'))!;

      // Имя длиннее ста байт лежит в архиве отдельной записью — и GNU, и POSIX
      // делают это по-своему; читать надо оба способа.
      expect(await readText(provider, node), 'deep');
    });

    test('не-tar даёт ошибку, а не пустую панель', () async {
      final path = p.join(work.path, 'garbage.tar');
      File(path).writeAsStringSync('это не архив, а просто текст с расширением');

      await expectLater(openTar(path), throwsA(isA<FsError>()));
    });

    test('длинный проход прерывается и говорит о ходе', () async {
      // Записей заведомо больше, чем шаг между точками отмены: иначе проход
      // кончится, ни разу не отдав управление, и проверять будет нечего.
      final many = Directory(p.join(work.path, 'many'))..createSync();
      for (var i = 0; i < 1500; i++) {
        File(p.join(many.path, 'file$i.txt')).writeAsStringSync('$i');
      }
      final path = await pack(['-cf', 'many.tar', 'many'], 'many.tar');

      final counted = <int>[];
      var calls = 0;
      await expectLater(
        readTarIndex(
          path,
          onEntries: counted.add,
          // Отмена — это исключение из `checkpoint`, и проход обязан его
          // выпустить наружу, а не проглотить и дочитать файл до конца.
          checkpoint: () async {
            calls++;
            throw const OperationCanceled();
          },
        ),
        throwsA(isA<OperationCanceled>()),
      );

      expect(calls, 1, reason: 'после отмены проход продолжился');
      expect(counted, isNotEmpty, reason: 'о ходе работы не сказано ни разу');
    });

    test('пустой архив открывается пустым, а не ошибкой', () async {
      final path = await pack(['-cf', 'empty.tar', '-T', '/dev/null'], 'empty.tar');

      // Пустой архив — это нулевые блоки и ничего больше: записей нет, но и
      // ошибки нет. `tar` делает такие сам.
      final provider = await openTar(path);
      expect(await namesIn(provider, '/'), isEmpty);
    });
  });

  group('gz', () {
    test('показывает одну запись с именем без расширения', () async {
      File(p.join(work.path, 'dump.sql')).writeAsStringSync('select 1;');
      await pack(['-czf', 'ignored.tar.gz', 'dump.sql'], 'ignored.tar.gz');
      final result = await Process.run('gzip', ['-k', 'dump.sql'], workingDirectory: work.path);
      expect(result.exitCode, 0);

      final provider = await GzipTreeProvider.open(await nodeAt(p.join(work.path, 'dump.sql.gz')));

      expect(await namesIn(provider, '/'), ['dump.sql']);
      final node = (await provider.resolvePath().run('/dump.sql'))!;
      expect(node.size, 'select 1;'.length, reason: 'размер берётся из хвоста gzip');
      expect(await readText(provider, node), 'select 1;');
    });

    test('у хозяина без прыжков размер неизвестен, а содержимое читается', () async {
      File(p.join(work.path, 'dump.sql')).writeAsStringSync('select 1;');
      final result = await Process.run('gzip', ['-k', 'dump.sql'], workingDirectory: work.path);
      expect(result.exitCode, 0);

      // Размер лежит в хвосте gzip, и достать его — это прыжок в конец файла.
      // Хозяин, который прыгать не умеет (файл на сервере), такого ответа не
      // даёт, и выдумывать его нельзя: сказать «не знаю» честнее, чем разжать
      // весь поток ради одного числа.
      final memory = InMemoryArchiveProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/dump.sql.gz', content: File(p.join(work.path, 'dump.sql.gz')).readAsBytesSync()),
      ])..capabilities = readOnlyCapabilities;
      final host = (await memory.resolvePath().run('/home/dump.sql.gz'))!;

      final provider = await GzipTreeProvider.open(host);
      final node = (await provider.resolvePath().run('/dump.sql'))!;

      expect(node.size, FsNode.unknownSize);
      expect(await readText(provider, node), 'select 1;', reason: 'поток читается и без размера');
    });

    test('у .tgz внутри лежит .tar', () async {
      await makeTree();
      await pack(['-czf', 'src.tgz', 'src'], 'src.tgz');

      final provider = await GzipTreeProvider.open(await nodeAt(p.join(work.path, 'src.tgz')));

      // Иначе внутрь него было бы не войти: расширения `.tgz` у tar-провайдера
      // нет, и по имени его никто бы не узнал.
      expect(await namesIn(provider, '/'), ['src.tar']);
    });

    test('имя без .gz вовсе не становится самим собой', () {
      // Иначе вход в архив стал бы бесконечным: внутри лежал бы файл с тем же
      // именем, который снова открывался бы как архив.
      expect(GzipTreeProvider.contentNameOf('dump'), 'dump.out');
      expect(GzipTreeProvider.contentNameOf('dump.sql.gz'), 'dump.sql');
      expect(GzipTreeProvider.contentNameOf('src.tgz'), 'src.tar');
    });
  });

  group('tar.gz — цепочкой', () {
    test('вход в архив, вход в .tar, чтение файла', () async {
      await makeTree();
      final path = await pack(['-czf', 'src.tar.gz', 'src'], 'src.tar.gz');

      // Первое звено: .gz показывает один .tar.
      final outer = await GzipTreeProvider.open(await nodeAt(path));
      final inner = (await outer.resolvePath().run('/src.tar'))!;
      expect(inner.name, 'src.tar');

      // Второе звено: tar-провайдер монтируется поверх записи .gz — и именно
      // здесь поток разжимается на диск, ровно один раз.
      final provider = await TarTreeProvider.open(inner, staging: staging);

      expect(await namesIn(provider, '/src'), containsAll(['lib', 'readme.md']));
      final readme = (await provider.resolvePath().run('/src/readme.md'))!;
      expect(await readText(provider, readme), '# hello');

      await (provider as ProviderLifecycle).dispose();
    });
  });
}
