import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Байтовый контракт на настоящей файловой системе.
void main() {
  late Directory temp;
  late String root;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_content');
    root = await temp.resolveSymbolicLinks();

    await File(p.join(root, 'notes.txt')).writeAsString('текст файла');
    await Link(p.join(root, 'link-to-notes')).create(p.join(root, 'notes.txt'));

    provider = LocalTreeProvider(homePath: root, readInIsolate: false);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<FsNode> nodeAt(String name) async => (await provider.resolvePath().run(p.join(root, name)))!;

  Future<DirectoryNode> rootDir() async => (await provider.resolvePath().run(root))! as DirectoryNode;

  Future<String> read(FsNode node, {int offset = 0}) async {
    final chunks = await (await provider.openRead(node, offset: offset)).toList();
    return utf8.decode([for (final chunk in chunks) ...chunk]);
  }

  test('провайдер локальной ФС отдаёт содержимое', () {
    expect(provider, isA<FileContentProvider>());
  });

  test('читает файл целиком', () async {
    expect(await read(await nodeAt('notes.txt')), 'текст файла');
  });

  test('offset пропускает начало — с него начнётся докачка', () async {
    // «текст » — шесть символов, из них пять двухбайтовых.
    expect(await read(await nodeAt('notes.txt'), offset: 11), 'файла');
  });

  test('ссылка читается как то, куда она ведёт', () async {
    // Содержимого у самой ссылки нет: читать в ней нечего, кроме цели.
    expect(await read(await nodeAt('link-to-notes')), 'текст файла');
  });

  test('ошибка чтения приходит ошибкой потока, а не исключением из вызова', () async {
    final node = await nodeAt('notes.txt');
    await File(p.join(root, 'notes.txt')).delete();

    // Открыть файл и читать его — разные моменты времени, и ошибка приходит
    // из второго; переведена она всё равно в FsError.
    final content = await provider.openRead(node);
    await expectLater(content.toList(), throwsA(isA<FsError>()));
  });

  test('пишет файл в каталог', () async {
    final sink = await provider.openWrite(await rootDir(), 'written.txt', length: 5);
    sink.add(utf8.encode('привет'));
    await sink.close();

    expect(await File(p.join(root, 'written.txt')).readAsString(), 'привет');
  });

  test('запись поверх существующего файла не оставляет старого хвоста', () async {
    final sink = await provider.openWrite(await rootDir(), 'notes.txt');
    sink.add(utf8.encode('коротко'));
    await sink.close();

    expect(await File(p.join(root, 'notes.txt')).readAsString(), 'коротко');
  });
}
