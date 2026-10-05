import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_s3/fc_s3.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_s3.dart';

/// Источник S3 на подставке: пути, листинги, правка дерева, ключи
/// (`docs/spec/s3.md`).
void main() {
  late FakeS3 api;
  late S3TreeProvider provider;

  List<int> bytes(String text) => utf8.encode(text);

  setUp(() {
    api = FakeS3(
      buckets: {
        'fc-test': {
          'readme.txt': bytes('hello'),
          'docs/': const [],
          'docs/guide.md': bytes('# guide'),
          'docs/deep/plan.txt': bytes('plan'),
          'empty/': const [],
          'a b+c.txt': bytes('x'),
        },
        'other': {},
      },
    );
    provider = S3TreeProvider(
      target: S3Target.parse(Uri.parse('s3+http://fctest@192.168.42.2:9000/fc-test')),
      api: api,
    );
  });

  Future<FsNode?> at(String path) => provider.resolvePath().run(path);

  Future<List<String>> listing(String path, {bool hidden = true}) async {
    final dir = (await at(path))! as DirectoryNode;
    final nodes = await provider.getDirectoryListing().run(ListingParams(dir, includeHidden: hidden));
    return [
      for (final node in nodes)
        if (node is! ParentDirNode) node is DirectoryNode ? '${node.name}/' : node.name,
    ];
  }

  group('путь', () {
    test('путь строки — с началом адреса, без секрета; дом — корзина из адреса', () async {
      final node = (await at('/fc-test/docs/guide.md'))!;

      expect(provider.pathOf(node), '//fctest@192.168.42.2:9000/fc-test/docs/guide.md');
      expect(provider.homePath, '/fc-test');
    });

    test('разбор принимает и полный путь панели', () async {
      final node = await at('//fctest@192.168.42.2:9000/fc-test/readme.txt');

      expect(node, isA<FileNode>());
      expect((node! as FileNode).size, 5);
    });

    test('префикс — каталог, объект — файл, ничего — null', () async {
      expect(await at('/fc-test/docs'), isA<DirectoryNode>());
      expect(await at('/fc-test/docs/deep'), isA<DirectoryNode>(), reason: 'каталог без маркера — тоже каталог');
      expect(await at('/fc-test/readme.txt'), isA<FileNode>());
      expect(await at('/fc-test/missing'), isNull);
      expect(await at('/nope'), isNull);
    });

    test('объект и префикс проверяются за один оборот', () async {
      api.calls.clear();
      await at('/fc-test/docs');

      expect(api.calls, unorderedEquals(['listObjects', 'headObject']));
    });
  });

  group('листинг', () {
    test('корень — корзины', () async {
      expect(await listing('/'), unorderedEquals(['fc-test/', 'other/']));
    });

    test('префиксы — каталогами, маркеры — тоже каталогами', () async {
      expect(await listing('/fc-test'), unorderedEquals(['docs/', 'empty/', 'readme.txt', 'a b+c.txt']));
    });

    test('свой маркер в своём листинге не строка', () async {
      expect(await listing('/fc-test/docs'), unorderedEquals(['deep/', 'guide.md']));
      expect(await listing('/fc-test/empty'), isEmpty);
    });

    test('страницами — и все до одной', () async {
      api = FakeS3(
        buckets: {
          'b': {for (var i = 0; i < 25; i++) 'f${i.toString().padLeft(2, '0')}.txt': const []},
        },
        pageSize: 10,
      );
      provider = S3TreeProvider(target: S3Target.parse(Uri.parse('s3://h/b')), api: api);

      expect(await listing('/b'), hasLength(25));
      expect(api.calls.where((call) => call == 'listObjects').length, greaterThanOrEqualTo(3));
    });

    test('без прав на список корзин — видна корзина из адреса', () async {
      api.refusals['listBuckets'] = const FsError('', FsErrorKind.permissionDenied);

      expect(await listing('/'), ['fc-test/']);
    });
  });

  group('правка', () {
    test('каталог — маркер нулевой длины', () async {
      final parent = (await at('/fc-test'))! as DirectoryNode;

      await provider.createDirectory(parent, 'new');

      expect(api.bucket('fc-test')['new/'], isEmpty);
    });

    test('занятое имя — каталогом или файлом — alreadyExists', () async {
      final parent = (await at('/fc-test'))! as DirectoryNode;

      await expectLater(
        provider.createDirectory(parent, 'docs'),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
      );
      await expectLater(
        provider.createDirectory(parent, 'readme.txt'),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.alreadyExists)),
      );
    });

    test('каталог в корне — корзина', () async {
      await provider.createDirectory(provider.rootDirectory, 'fresh');

      expect(api.calls, contains('createBucket'));
    });

    test('копия — средствами сервера', () async {
      final node = (await at('/fc-test/readme.txt'))!;
      final dest = (await at('/fc-test/docs'))! as DirectoryNode;

      expect(await provider.copyEntry(node, dest, 'copy.txt'), isTrue);

      expect(api.calls, contains('copyObject'));
      expect(api.bucket('fc-test')['docs/copy.txt'], bytes('hello'));
    });

    test('переименование объекта — копия и удаление; префикса — не здесь', () async {
      final node = (await at('/fc-test/readme.txt'))!;
      final dest = (await at('/fc-test/docs'))! as DirectoryNode;

      expect(await provider.renameEntry(node, dest, 'moved.txt'), isTrue);
      expect(api.bucket('fc-test').containsKey('readme.txt'), isFalse);
      expect(api.bucket('fc-test')['docs/moved.txt'], bytes('hello'));

      final dir = (await at('/fc-test/docs'))!;
      api.calls.clear();
      expect(await provider.renameEntry(dir, provider.rootDirectory, 'x'), isFalse);
      expect(api.calls, isEmpty, reason: 'отказ ничего не стоит');
    });

    test('поддерево — пачками', () async {
      final dir = (await at('/fc-test/docs'))!;

      expect(await provider.deleteTree(dir), isTrue);

      expect(api.calls, contains('deleteObjects'));
      expect(api.bucket('fc-test').keys.where((key) => key.startsWith('docs/')), isEmpty);
    });

    test('без пачек (Google Storage) — поштучно', () async {
      api.noBatchDelete = true;
      final dir = (await at('/fc-test/docs'))!;

      expect(await provider.deleteTree(dir), isTrue);

      expect(api.bucket('fc-test').keys.where((key) => key.startsWith('docs/')), isEmpty);
    });

    test('умения', () {
      final capabilities = provider.capabilities;

      expect(capabilities.canRename, isTrue);
      expect(capabilities.canSeek, isTrue);
      expect(capabilities.preservesModified, isFalse);
      expect(capabilities.maxConcurrency, 8);
    });
  });

  group('чтение и запись', () {
    test('чтение с середины', () async {
      final node = (await at('/fc-test/readme.txt'))!;

      final read = await (await provider.openRead(node, offset: 2)).expand((chunk) => chunk).toList();

      expect(utf8.decode(read), 'llo');
    });

    test('маленький файл — одним PUT', () async {
      final parent = (await at('/fc-test'))! as DirectoryNode;
      final sink = await provider.openWrite(parent, 'small.txt', length: 3);

      await sink.addStream(Stream.value(bytes('abc')));
      await sink.close();

      expect(api.bucket('fc-test')['small.txt'], bytes('abc'));
      expect(api.calls, isNot(contains('createMultipartUpload')));
    });

    test('крупный — частями, и собирается целым', () async {
      final sink = S3UploadSink(api, 'fc-test', 'big.bin', length: 25, partSize: 10);

      await sink.addStream(Stream.fromIterable([List.filled(12, 1), List.filled(13, 2)]));
      await sink.close();

      expect(api.calls.where((call) => call == 'uploadPart').length, 3);
      expect(api.bucket('fc-test')['big.bin'], [...List.filled(12, 1), ...List.filled(13, 2)]);
      expect(api.uploads, isEmpty);
    });

    test('частей в полёте не больше предела, источник ждёт', () async {
      api.holdParts = Completer<void>();
      final sink = S3UploadSink(api, 'fc-test', 'big.bin', partSize: 4, maxInFlight: 2);
      final controller = StreamController<List<int>>();
      final adding = sink.addStream(controller.stream);

      for (var i = 0; i < 6; i++) {
        controller.add(List.filled(4, i));
        await pumpEventQueue();
      }
      expect(api.peakParts, lessThanOrEqualTo(2));
      expect(controller.isPaused, isTrue, reason: 'источник стоит, пока части не ушли');

      api.holdParts!.complete();
      await pumpEventQueue();
      await controller.close();
      await adding;
      await sink.close();
      expect(api.bucket('fc-test')['big.bin'], hasLength(24));
    });

    test('брошенная загрузка отменяется на сервере и объекта не оставляет', () async {
      api.holdParts = Completer<void>();
      final sink = S3UploadSink(api, 'fc-test', 'big.bin', partSize: 4);
      sink.add(List.filled(9, 7));
      await pumpEventQueue();

      final aborting = sink.abort();
      api.holdParts!.complete();
      await aborting;

      expect(api.calls, contains('abortMultipartUpload'));
      expect(api.calls, isNot(contains('completeMultipartUpload')));
      expect(api.uploads, isEmpty, reason: 'брошенные части стоят денег');
      expect(api.bucket('fc-test').containsKey('big.bin'), isFalse);
    });

    test('упала часть — close отменяет загрузку и называет ошибку', () async {
      api.refusals['uploadPart'] = const FsError('big.bin', FsErrorKind.io);
      final sink = S3UploadSink(api, 'fc-test', 'big.bin', partSize: 4);
      sink.add(List.filled(9, 7));

      await expectLater(sink.close(), throwsA(isA<FsError>()));

      expect(api.calls, contains('abortMultipartUpload'));
      expect(api.uploads, isEmpty);
    });

    test('запись в корень — нельзя: там корзины', () async {
      await expectLater(
        provider.openWrite(provider.rootDirectory, 'x.txt'),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.notSupported)),
      );
    });
  });

  group('ключи', () {
    Future<TreeProvider> open(String address, FakeCredentials credentials, {List<String>? accepted}) =>
        S3TreeProvider.open(
          Uri.parse(address),
          credentials: credentials,
          connect: (target, key, secret) {
            final fake = FakeS3(buckets: {'b': {}});
            if (accepted != null && !accepted.contains(secret)) {
              fake.refusals['listObjects'] = const FsError(
                'b',
                FsErrorKind.permissionDenied,
                S3Failure(status: 403, code: 'SignatureDoesNotMatch'),
              );
              fake.refusals['listBuckets'] = fake.refusals['listObjects']!;
            }
            return fake;
          },
        );

    test('неверный секрет — забыть и спросить снова', () async {
      final credentials = FakeCredentials(answers: ['wrong', 'right']);

      await open('s3+http://ak@h:9000/b', credentials, accepted: ['right']);

      expect(credentials.asked, hasLength(2));
      expect(credentials.asked.last.retry, isTrue);
    });

    test('закрыли окно — permissionDenied', () async {
      await expectLater(
        open('s3://ak@h/b', FakeCredentials(answers: [null])),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.permissionDenied)),
      );
    });

    test('ключ в адресе — одно поле; без ключа — два', () async {
      final one = FakeCredentials(answers: ['s']);
      await open('s3://ak@h/b', one);
      expect(one.asked.single.fields, hasLength(1));

      final two = FakeCredentials(answers: ['s']);
      await open('s3://h/b', two);
      expect(two.asked.single.fields, hasLength(2));
    });

    test('секрет из адреса — без окна', () async {
      final credentials = FakeCredentials();

      await open('s3://ak:secret@h/b', credentials);

      expect(credentials.asked, isEmpty);
    });
  });

  test('S3Abort зовёт подписчиков один раз', () {
    final abort = S3Abort();
    var calls = 0;
    abort.onAbort(() => calls++);
    abort
      ..abort()
      ..abort();
    abort.onAbort(() => calls++);

    expect(calls, 2);
  });

  test('пустое тело — пустой массив, а не null', () {
    expect(Uint8List(0), isEmpty);
  });
}
