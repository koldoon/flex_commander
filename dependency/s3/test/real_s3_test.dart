import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_s3/fc_s3.dart';
import 'package:flutter_test/flutter_test.dart';

/// Живое хранилище — полный круг (`docs/spec/s3.md`, §16).
///
/// ```
/// FC_S3_TEST_HOST=s3+http://fctest@192.168.42.2:9000/fc-test \
/// FC_S3_TEST_SECRET=… flutter test --timeout 120s s3/test/real_s3_test.dart
/// ```
///
/// Всё — в своём префиксе `fc-live-<время>/`, и убирается за собой.
void main() {
  final address = Platform.environment['FC_S3_TEST_HOST'];
  if (address == null || address.isEmpty) {
    // Пропущенный тест виден в прогоне — молча исчезать он не должен.
    test('живое S3 не проверяется: нет FC_S3_TEST_HOST', () {}, skip: 'нет FC_S3_TEST_HOST');
    return;
  }
  final secret = Platform.environment['FC_S3_TEST_SECRET'];
  final target = S3Target.parse(Uri.parse(address));
  final bucket = target.bucket!;
  final prefix = 'fc-live-${DateTime.now().millisecondsSinceEpoch}';

  late S3Client client;
  late S3TreeProvider provider;

  setUpAll(() {
    if (secret == null || secret.isEmpty) {
      fail('FC_S3_TEST_HOST задан, а FC_S3_TEST_SECRET — нет');
    }
    client = S3Client(target, accessKey: target.accessKey!, secretKey: secret);
    provider = S3TreeProvider(target: target, api: client);
  });

  tearDownAll(() async {
    final dir = await provider.resolvePath().run('/$bucket/$prefix');
    if (dir != null) {
      await provider.deleteTree(dir);
    }
    await client.close();
  });

  Future<DirectoryNode> home() async {
    final root = (await provider.resolvePath().run('/$bucket'))! as DirectoryNode;
    return (await provider.lookup(root, prefix)) as DirectoryNode? ?? await provider.createDirectory(root, prefix);
  }

  Future<List<int>> read(FsNode node, {int offset = 0}) async =>
      (await provider.openRead(node, offset: offset)).expand((chunk) => chunk).toList();

  Future<void> write(DirectoryNode parent, String name, List<int> data, {int? length}) async {
    final sink = await provider.openWrite(parent, name, length: length);
    await sink.addStream(
      Stream.fromIterable([
        for (var i = 0; i < data.length; i += 1 << 20)
          data.sublist(i, i + (1 << 20) > data.length ? data.length : i + (1 << 20)),
      ]),
    );
    await sink.close();
  }

  const timeout = Timeout(Duration(seconds: 120));

  test('вход и список корзин', () async {
    final buckets = await client.listBuckets();

    expect(buckets.map((b) => b.name), contains(bucket));
  }, timeout: timeout);

  test('каталог, маленький файл, чтение с середины', () async {
    final dir = await home();
    await write(dir, 'small.txt', utf8.encode('hello world'), length: 11);

    final node = (await provider.lookup(dir, 'small.txt'))!;
    expect(node, isA<FileNode>());
    expect(utf8.decode(await read(node, offset: 6)), 'world');
  }, timeout: timeout);

  test('крупный файл — частями, читается обратно тем же', () async {
    final dir = await home();
    final data = Uint8List(20 * 1024 * 1024 + 123);
    for (var i = 0; i < data.length; i++) {
      data[i] = i * 31 % 251;
    }

    await write(dir, 'big.bin', data, length: data.length);

    final node = (await provider.lookup(dir, 'big.bin'))! as FileNode;
    expect(node.size, data.length);
    expect(sha256.convert(await read(node)).toString(), sha256.convert(data).toString());
  }, timeout: timeout);

  test('брошенная многочастная загрузка не оставляет ни объекта, ни частей', () async {
    final dir = await home();
    final sink = await provider.openWrite(dir, 'aborted.bin') as S3UploadSink;
    sink.add(Uint8List(S3UploadSink.unknownPart + 10));
    await Future<void>.delayed(const Duration(seconds: 2));

    await sink.abort();

    expect(await provider.lookup(dir, 'aborted.bin'), isNull);
  }, timeout: timeout);

  test('трудные имена: пробел, плюс, процент, кириллица, двоеточие', () async {
    final dir = await home();
    const names = ['a b.txt', 'plus+sign.txt', 'pct%x.txt', 'кириллица.txt', 'col:on.txt', 'tilde~.txt'];
    for (final name in names) {
      await write(dir, name, utf8.encode(name), length: utf8.encode(name).length);
    }

    final listed = await provider.listChildren(dir);
    for (final name in names) {
      final node = listed.firstWhere((node) => node.name == name, orElse: () => fail('нет «$name» в листинге'));
      expect(utf8.decode(await read(node)), name, reason: 'читается тот же объект');
    }
  }, timeout: timeout);

  test('копия и переименование — средствами сервера', () async {
    final dir = await home();
    await write(dir, 'orig.txt', utf8.encode('orig'), length: 4);
    final orig = (await provider.lookup(dir, 'orig.txt'))!;

    expect(await provider.copyEntry(orig, dir, 'copy.txt'), isTrue);
    expect(utf8.decode(await read((await provider.lookup(dir, 'copy.txt'))!)), 'orig');

    expect(await provider.renameEntry(orig, dir, 'renamed.txt'), isTrue);
    expect(await provider.lookup(dir, 'orig.txt'), isNull);
    expect(await provider.lookup(dir, 'renamed.txt'), isNotNull);
  }, timeout: timeout);

  test('листинг страницами', () async {
    final dir = await home();
    final paged = await provider.createDirectory(dir, 'paged');
    for (var i = 0; i < 5; i++) {
      await write(paged, 'f$i.txt', [i], length: 1);
    }
    final (b, key) = (bucket, '$prefix/paged/');

    final first = await client.listObjects(b, prefix: key, maxKeys: 2);
    expect(first.truncated, isTrue);
    final second = await client.listObjects(b, prefix: key, maxKeys: 2, token: first.nextToken);
    expect(second.objects, isNotEmpty);
  }, timeout: timeout);

  test('неверный секрет — ключ отвергнут', () async {
    final wrong = S3Client(target, accessKey: target.accessKey!, secretKey: 'wrong');
    try {
      await wrong.listBuckets();
      fail('неверный секрет прошёл');
    } on FsError catch (error) {
      expect(credentialRejected(error), isTrue);
    } finally {
      await wrong.close();
    }
  }, timeout: timeout);
}
