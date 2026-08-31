import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_tar/fc_tar.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Упаковка в tar и tar.gz.
///
/// Готовый архив разбирается **системным `tar`**: своим же читателем проверять
/// свой же писатель — значит сойтись на одинаковой ошибке дважды.
void main() {
  late Directory work;
  late String source;
  late String target;
  late LocalTreeProvider disk;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('fc_tar_create');
    source = p.join(work.path, 'from');
    target = p.join(work.path, 'to');
    Directory(source).createSync();
    Directory(target).createSync();

    Directory(p.join(source, 'src', 'lib')).createSync(recursive: true);
    File(p.join(source, 'src', 'readme.md')).writeAsStringSync('# hello');
    File(p.join(source, 'src', 'lib', 'main.dart')).writeAsStringSync('void main() {}');
    File(p.join(source, 'src', 'run.sh')).writeAsStringSync('#!/bin/sh\n');
    Process.runSync('chmod', ['755', p.join(source, 'src', 'run.sh')]);
    Link(p.join(source, 'src', 'link.md')).createSync('readme.md');

    disk = LocalTreeProvider(homePath: work.path, readInIsolate: false);
  });

  tearDown(() async {
    await work.delete(recursive: true);
  });

  Future<FsNode> nodeAt(String path) async => (await disk.resolvePath().run(path))!;

  /// Пакует `from/src` в `to/<name>`.
  Future<String> pack(String name, {TarFormat format = TarFormat.gzip, bool followLinks = false}) async {
    final command = CreateTarArchiveCommand(staging: LocalStagingArea(root: work));
    final destination = await nodeAt(target) as DirectoryNode;

    await command.packOperation().run(
      TarPackParams([await nodeAt(p.join(source, 'src'))], destination, name, format: format, followLinks: followLinks),
    );

    final path = p.join(target, name);
    expect(File(path).existsSync(), isTrue, reason: 'архив не появился');
    return path;
  }

  /// Что видит системный `tar` внутри архива.
  Future<List<String>> listing(String archivePath) async {
    final result = await Process.run('tar', ['-tf', archivePath]);
    expect(result.exitCode, 0, reason: 'tar: ${result.stderr}');
    return (result.stdout as String).split('\n').where((line) => line.isNotEmpty).toList();
  }

  test('.tar собирается и читается системным tar', () async {
    final path = await pack('src.tar', format: TarFormat.plain);

    expect(await listing(path), containsAll(['src/', 'src/readme.md', 'src/lib/main.dart']));
  });

  test('.tar.gz — тот же архив, только сжатый', () async {
    final path = await pack('src.tar.gz');

    // Заголовок gzip: два байта, по которым его узнают все.
    final head = await File(path).openRead(0, 2).expand((chunk) => chunk).toList();
    expect(head, [0x1f, 0x8b]);
    expect(await listing(path), contains('src/readme.md'));
  });

  test('.tgz — тот же tar.gz, только имя короче', () async {
    final path = await pack('src.tgz', format: TarFormat.tgz);

    // Отличие от `.tar.gz` — ровно в имени файла: байты те же, и системный
    // `tar` разбирает его тем же ключом.
    final head = await File(path).openRead(0, 2).expand((chunk) => chunk).toList();
    expect(head, [0x1f, 0x8b]);
    expect(await listing(path), contains('src/readme.md'));
  });

  test('содержимое доходит побайтно', () async {
    final path = await pack('src.tar', format: TarFormat.plain);

    final result = await Process.run('tar', ['-xOf', path, 'src/lib/main.dart']);
    expect(result.exitCode, 0, reason: 'tar: ${result.stderr}');
    expect(result.stdout, 'void main() {}');
  });

  test('права и ссылки доходят до архива', () async {
    final path = await pack('src.tar', format: TarFormat.plain);

    final result = await Process.run('tar', ['-tvf', path]);
    final lines = (result.stdout as String).split('\n');

    // Права — главное отличие tar от zip.
    expect(lines.firstWhere((line) => line.endsWith('src/run.sh')), contains('rwxr-xr-x'));
    // Ссылка ложится ссылкой, а не копией того, на что указывает.
    expect(lines.firstWhere((line) => line.contains('src/link.md')), contains('-> readme.md'));
  });

  test('по ссылке идут, если попросили', () async {
    final path = await pack('src.tar', format: TarFormat.plain, followLinks: true);

    final result = await Process.run('tar', ['-tvf', path]);
    expect((result.stdout as String).split('\n').firstWhere((line) => line.contains('link.md')), isNot(contains('->')));

    final content = await Process.run('tar', ['-xOf', path, 'src/link.md']);
    expect(content.stdout, '# hello');
  });

  test('длинное имя разбирается системным tar', () async {
    final deep = p.join(source, 'src', List.filled(10, 'длинное-имя-каталога').join('/'));
    Directory(deep).createSync(recursive: true);
    File(p.join(deep, 'deep.txt')).writeAsStringSync('deep');

    final path = await pack('long.tar', format: TarFormat.plain);

    final result = await Process.run('tar', ['-xOf', path, p.relative(p.join(deep, 'deep.txt'), from: source)]);
    expect(result.exitCode, 0, reason: 'tar: ${result.stderr}');
    expect(result.stdout, 'deep');
  });

  test('свой читатель видит то же, что и системный', () async {
    final path = await pack('src.tar', format: TarFormat.plain);

    final provider = await TarTreeProvider.open(await nodeAt(path), staging: LocalStagingArea(root: work));
    final node = (await provider.resolvePath().run('/src/readme.md'))!;
    final content = await (provider as FileContentProvider).openRead(node);

    expect(String.fromCharCodes(await content.expand((chunk) => chunk).toList()), '# hello');
  });

  group('имя архива', () {
    test('расширение дописывается по формату', () {
      expect(CreateTarArchiveCommand.withExtension('src', TarFormat.plain), 'src.tar');
      expect(CreateTarArchiveCommand.withExtension('src', TarFormat.gzip), 'src.tar.gz');
      expect(CreateTarArchiveCommand.withExtension('src', TarFormat.tgz), 'src.tgz');
    });

    test('уже написанное расширение не задваивается', () {
      expect(CreateTarArchiveCommand.withExtension('src.tar', TarFormat.plain), 'src.tar');
      expect(CreateTarArchiveCommand.withExtension('src.tar.gz', TarFormat.gzip), 'src.tar.gz');
      expect(CreateTarArchiveCommand.withExtension('src.tgz', TarFormat.tgz), 'src.tgz');
    });

    test('чужое расширение заменяется, а не приписывается', () {
      // `.tgz` — отдельный пункт в окне, и выбор формата теперь решает всё:
      // набранное расширение уступает выбранному, иначе имя врало бы о
      // содержимом.
      expect(CreateTarArchiveCommand.withExtension('src.tar', TarFormat.gzip), 'src.tar.gz');
      expect(CreateTarArchiveCommand.withExtension('src.tgz', TarFormat.gzip), 'src.tar.gz');
      expect(CreateTarArchiveCommand.withExtension('src.tar.gz', TarFormat.tgz), 'src.tgz');
      expect(CreateTarArchiveCommand.withExtension('src.tar.gz', TarFormat.plain), 'src.tar');
    });

    test('расширение самого файла не трогается', () {
      // `dump.sql` — это имя файла, а не архива: `.sql` в списке архивных
      // расширений не значится и уцелеет.
      expect(CreateTarArchiveCommand.withExtension('dump.sql', TarFormat.gzip), 'dump.sql.tar.gz');
    });
  });
}
