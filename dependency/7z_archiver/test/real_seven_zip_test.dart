import 'dart:convert';
import 'dart:io';

import 'package:fc_7z_archiver/fc_7z_archiver.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/modules/local_fs/local_process_runner.dart';
import 'package:flex_commander/modules/local_fs/local_staging_area.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Настоящая программа, настоящий архив.
///
/// Всё остальное в модуле проверяется на подставном запускателе — иначе тесты
/// требовали бы 7-Zip на каждой машине. Но подставка проверяет наши
/// предположения о программе, а не саму программу: разбор её вывода, ключи,
/// коды возврата. Этот тест проверяет предположения — и потому включается
/// только там, где программа есть.
///
/// Чтобы он заработал: `brew install sevenzip` (или `apt install p7zip-full`).
void main() {
  const processes = LocalProcessRunner();

  late Directory temp;
  late SevenZipCli cli;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_7z_real');
    cli = SevenZipCli(processes: processes);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('программа найдена — или тест пропущен', () async {
    final found = await cli.available;
    if (!found) {
      markTestSkipped('7-Zip не установлен: brew install sevenzip');
    }
    expect(true, isTrue);
  });

  test('созданный архив читается обратно', () async {
    if (!await cli.available) {
      markTestSkipped('7-Zip не установлен: brew install sevenzip');
      return;
    }

    final root = await temp.resolveSymbolicLinks();
    final source = p.join(root, 'source');
    await Directory(p.join(source, 'docs')).create(recursive: true);
    await File(p.join(source, 'notes.txt')).writeAsString('заметки');
    await File(p.join(source, 'docs', 'guide.txt')).writeAsString('руководство');

    // Упаковка — тем же вызовом, каким её делает модуль записи.
    final archivePath = p.join(root, 'sample.7z');
    final list = File(p.join(root, 'list.txt'))..writeAsStringSync('notes.txt\ndocs');
    await cli.add(archivePath, workingDirectory: source, listFile: list.path);

    expect(File(archivePath).existsSync(), isTrue);

    // Чтение — через провайдер, как это делает панель.
    final local = LocalTreeProvider();
    final host = (await local.resolvePath(archivePath).result)!;
    final provider = await SevenZipTreeProvider.open(host, staging: LocalStagingArea(root: temp), cli: cli);
    addTearDown(() => (provider as ProviderLifecycle).dispose());

    final names = (await provider.listChildren(provider.rootDirectory)).map((node) => node.name).toList()..sort();
    expect(names, ['docs', 'notes.txt']);

    final entry = (await provider.resolvePath('/docs/guide.txt').result)! as FileNode;
    expect(entry.size, utf8.encode('руководство').length);

    final bytes = await (provider as FileContentProvider).openRead(entry);
    expect(utf8.decode(await bytes.expand((chunk) => chunk).toList()), 'руководство');
  });

  test('запись и удаление меняют настоящий архив', () async {
    if (!await cli.available) {
      markTestSkipped('7-Zip не установлен: brew install sevenzip');
      return;
    }

    final root = await temp.resolveSymbolicLinks();
    final source = p.join(root, 'source');
    await Directory(source).create(recursive: true);
    await File(p.join(source, 'first.txt')).writeAsString('первый');

    final archivePath = p.join(root, 'sample.7z');
    final list = File(p.join(root, 'list.txt'))..writeAsStringSync('first.txt');
    await cli.add(archivePath, workingDirectory: source, listFile: list.path);

    final local = LocalTreeProvider();
    final host = (await local.resolvePath(archivePath).result)!;
    final provider =
        await SevenZipTreeProvider.open(host, staging: LocalStagingArea(root: temp), cli: cli)
            as WritableSevenZipTreeProvider;

    // Дописать.
    final sink = await provider.openWrite(provider.rootDirectory, 'second.txt');
    sink.add(utf8.encode('второй'));
    await sink.close();

    var names = (await provider.listChildren(provider.rootDirectory)).map((node) => node.name).toList()..sort();
    expect(names, ['first.txt', 'second.txt'], reason: 'оглавление перечитано у самой программы');

    // Удалить.
    await provider.deleteEntry((await provider.resolvePath('/first.txt').result)!);

    names = (await provider.listChildren(provider.rootDirectory)).map((node) => node.name).toList();
    expect(names, ['second.txt']);

    await provider.dispose();
  });

  test('имя с подстановочными символами читается как имя', () async {
    if (!await cli.available) {
      markTestSkipped('7-Zip не установлен: brew install sevenzip');
      return;
    }

    // Ровно тот случай, ради которого нужен `-spd`: без него `[1].txt` было бы
    // понято как образец.
    final root = await temp.resolveSymbolicLinks();
    final source = p.join(root, 'source');
    await Directory(source).create(recursive: true);
    await File(p.join(source, '[1].txt')).writeAsString('скобки');

    final archivePath = p.join(root, 'sample.7z');
    final list = File(p.join(root, 'list.txt'))..writeAsStringSync('[1].txt');
    await cli.add(archivePath, workingDirectory: source, listFile: list.path);

    final content = await cli.read(archivePath, '[1].txt').expand((chunk) => chunk).toList();
    expect(utf8.decode(content), 'скобки');
  });
}
