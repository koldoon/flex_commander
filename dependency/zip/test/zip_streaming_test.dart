import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Чтение записи потоком: сжатые байты берутся прямо из файла, а разжимает их
/// системный zlib по мере запроса.
///
/// Главное здесь — **сверка**: то же содержимое, прочитанное новым путём,
/// обязано совпасть со старым байт в байт. Ошибиться легче всего на длине
/// локального заголовка — имя и дополнительное поле у него переменные.
void main() {
  late Directory temp;
  late String root;
  late String archivePath;
  late LocalTreeProvider disk;

  /// Содержимое записи, собранное из потока провайдера.
  Future<List<int>> read(TreeProvider provider, String path, {int offset = 0}) async {
    final node = (await provider.resolvePath().run(path))!;
    final stream = await (provider as FileContentProvider).openRead(node, offset: offset);
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<TreeProvider> mounted() async {
    final host = (await disk.resolvePath().run(archivePath))!;
    return ZipTreeProvider.open(host, credentials: FakeCredentials(), staging: const LocalStagingArea());
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_zip_stream');
    root = await temp.resolveSymbolicLinks();
    archivePath = p.join(root, 'sample.zip');
    disk = LocalTreeProvider(homePath: root, readInIsolate: false);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('сжатая и несжатая записи читаются верно', () async {
    // Хорошо сжимаемое и несжимаемое: у первого метод будет deflate, у второго
    // упаковщик обычно оставляет «как есть».
    final compressible = utf8.encode('строка, повторённая много раз. ' * 500);
    final random = Random(42);
    final incompressible = List<int>.generate(50000, (_) => random.nextInt(256));

    final archive =
        Archive()
          ..add(ArchiveFile.bytes('text.txt', compressible))
          ..add(ArchiveFile.bytes('noise.bin', incompressible))
          ..add(ArchiveFile.bytes('empty.txt', const <int>[]));
    await File(archivePath).writeAsBytes(ZipEncoder().encodeBytes(archive));

    final zip = await mounted();
    addTearDown(() => (zip as ProviderLifecycle).dispose());

    expect(await read(zip, '/text.txt'), compressible);
    expect(await read(zip, '/noise.bin'), incompressible);
    expect(await read(zip, '/empty.txt'), isEmpty);
  });

  test('оглавление даёт сведения для потока — и путь этот и правда быстрый', () async {
    final compressible = utf8.encode('повторяем и повторяем. ' * 500);
    final archive =
        Archive()
          ..add(ArchiveFile.bytes('text.txt', compressible))
          ..add(ArchiveFile.bytes('stored.bin', List<int>.generate(2000, (i) => i % 256)));
    await File(archivePath).writeAsBytes(ZipEncoder().encodeBytes(archive));

    final raw = await readRawEntries(archivePath);
    expect(raw.keys, containsAll(<String>['text.txt', 'stored.bin']));
    // Читаем сами: не зашифровано и метод из тех двух, что мы понимаем.
    expect(raw['text.txt']!.readable, isTrue);
    expect(raw['text.txt']!.method, ZipRawEntry.deflate);
    expect(raw['text.txt']!.compressedSize, lessThan(compressible.length), reason: 'сжалось');
    expect(raw['text.txt']!.headerOffset, greaterThanOrEqualTo(0));
  });

  test('прочитанное потоком совпадает с тем, что даёт библиотека', () async {
    // Сверка, обещанная спекой: старый путь и новый обязаны совпасть байт в
    // байт — на записях разного вида.
    final entries = <String, List<int>>{
      'text.txt': utf8.encode('строка. ' * 3000),
      'noise.bin': List<int>.generate(30000, (_) => Random(7).nextInt(256)),
      'nested/deep/name-with-длинным-именем.dat': utf8.encode('вложенное содержимое'),
      'empty': const <int>[],
    };
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.add(ArchiveFile.bytes(entry.key, entry.value));
    }
    await File(archivePath).writeAsBytes(ZipEncoder().encodeBytes(archive));

    final zip = await mounted();
    addTearDown(() => (zip as ProviderLifecycle).dispose());

    final decoded = ZipDecoder().decodeBytes(await File(archivePath).readAsBytes());
    for (final entry in entries.entries) {
      final library = decoded.findFile(entry.key)!.readBytes()!;
      expect(await read(zip, '/${entry.key}'), library, reason: entry.key);
    }
  });

  test('длинное имя и дополнительное поле не сбивают начало данных', () async {
    // Локальный заголовок переменной длины — ровно то место, где промах на
    // пару байт даёт мусор вместо содержимого.
    final name = '${'каталог-с-длинным-именем/' * 6}файл.txt';
    final content = utf8.encode('содержимое за длинным заголовком');
    final archive = Archive()..add(ArchiveFile.bytes(name, content));
    await File(archivePath).writeAsBytes(ZipEncoder().encodeBytes(archive));

    final zip = await mounted();
    addTearDown(() => (zip as ProviderLifecycle).dispose());

    expect(await read(zip, '/$name'), content);
  });

  test('чтение со смещением отдаёт хвост', () async {
    final content = utf8.encode('0123456789' * 1000);
    await File(archivePath).writeAsBytes(ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.bytes('a.txt', content))));

    final zip = await mounted();
    addTearDown(() => (zip as ProviderLifecycle).dispose());

    expect(await read(zip, '/a.txt', offset: 9995), content.sublist(9995));
  });

  test('читатель, ушедший раньше времени, не роняет чтение', () async {
    final content = utf8.encode('строка. ' * 20000);
    await File(
      archivePath,
    ).writeAsBytes(ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.bytes('big.txt', content))));

    final zip = await mounted();
    addTearDown(() => (zip as ProviderLifecycle).dispose());

    final node = (await zip.resolvePath().run('/big.txt'))!;
    final stream = await (zip as FileContentProvider).openRead(node);
    // Взяли первый кусок и ушли: так делает отмена работы.
    final first = await stream.first;
    expect(first, isNotEmpty);

    // Архив после этого по-прежнему читается целиком.
    expect(await read(zip, '/big.txt'), content);
  });
}
