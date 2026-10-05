import 'dart:async';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_s3/fc_s3.dart';

/// Хранилище в памяти — подставка за [S3Api], как `FakeFtp` у FTP.
///
/// Листинг честный: префиксы уровня через `/`, маркеры каталогов — ключи с `/`
/// на конце, страницы по [pageSize].
class FakeS3 implements S3Api {
  FakeS3({Map<String, Map<String, List<int>>> buckets = const {}, this.pageSize = 1000})
    : _buckets = {
        for (final entry in buckets.entries) entry.key: {...entry.value},
      };

  final Map<String, Map<String, List<int>>> _buckets;
  final int pageSize;

  /// Что звали — по порядку.
  final List<String> calls = [];

  /// Отказы: имя вызова → ошибка.
  final Map<String, FsError> refusals = {};

  /// Нет пачки удалений (как у Google Storage).
  bool noBatchDelete = false;

  /// Незавершённые многочастные загрузки: номер → (корзина, ключ, части).
  final Map<String, (String, String, Map<int, List<int>>)> uploads = {};
  var _nextUpload = 0;

  Map<String, List<int>> bucket(String name) => _buckets[name]!;

  void _call(String name) {
    calls.add(name);
    if (refusals[name] case final error?) {
      throw error;
    }
  }

  Map<String, List<int>> _bucket(String name) =>
      _buckets[name] ?? (throw FsError(name, FsErrorKind.notFound, const S3Failure(status: 404, code: 'NoSuchBucket')));

  @override
  Future<List<S3Bucket>> listBuckets() async {
    _call('listBuckets');
    return [for (final name in _buckets.keys) S3Bucket(name: name)];
  }

  @override
  Future<S3Page> listObjects(
    String bucket, {
    String prefix = '',
    String? delimiter = '/',
    String? token,
    int maxKeys = 1000,
  }) async {
    _call('listObjects');
    final keys = (_bucket(bucket).keys.where((key) => key.startsWith(prefix)).toList()..sort());
    final objects = <S3Object>[];
    final prefixes = <String>{};
    for (final key in keys) {
      final rest = key.substring(prefix.length);
      final slash = delimiter == null ? -1 : rest.indexOf(delimiter);
      if (slash >= 0) {
        prefixes.add('$prefix${rest.substring(0, slash + 1)}');
      } else {
        objects.add(S3Object(key: key, size: _bucket(bucket)[key]!.length));
      }
    }
    // Страницы — по общему списку, как у настоящего: объекты и префиксы вперемешку.
    final all = [
      for (final object in objects) (object.key, object as Object),
      for (final prefix in prefixes) (prefix, prefix as Object),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final start = token == null ? 0 : int.parse(token);
    final size = maxKeys < pageSize ? maxKeys : pageSize;
    final slice = all.skip(start).take(size).toList();
    final next = start + slice.length < all.length ? '${start + slice.length}' : null;
    return S3Page(
      objects: [
        for (final item in slice)
          if (item.$2 is S3Object) item.$2 as S3Object,
      ],
      prefixes: [
        for (final item in slice)
          if (item.$2 is String) item.$2 as String,
      ],
      nextToken: next,
    );
  }

  @override
  Future<S3Object?> headObject(String bucket, String key) async {
    _call('headObject');
    final data = _bucket(bucket)[key];
    return data == null ? null : S3Object(key: key, size: data.length);
  }

  @override
  Future<Stream<List<int>>> getObject(String bucket, String key, {int offset = 0}) async {
    _call('getObject');
    final data = _bucket(bucket)[key] ?? (throw FsError(key, FsErrorKind.notFound));
    return Stream.value(data.sublist(offset));
  }

  @override
  Future<void> putObject(String bucket, String key, Uint8List body, {S3Abort? abort}) async {
    _call('putObject');
    _bucket(bucket)[key] = List.of(body);
  }

  @override
  Future<String> createMultipartUpload(String bucket, String key) async {
    _call('createMultipartUpload');
    final id = 'up${_nextUpload++}';
    uploads[id] = (bucket, key, {});
    return id;
  }

  /// Придержать части: пока не отпустят, загрузка «идёт».
  Completer<void>? holdParts;

  /// Сколько частей сейчас в полёте и сколько было разом больше всего.
  int partsInFlight = 0;
  int peakParts = 0;

  @override
  Future<String> uploadPart(
    String bucket,
    String key,
    String uploadId,
    int number,
    Uint8List body, {
    S3Abort? abort,
  }) async {
    _call('uploadPart');
    partsInFlight++;
    peakParts = partsInFlight > peakParts ? partsInFlight : peakParts;
    try {
      if (holdParts case final hold?) {
        await hold.future;
      }
      if (abort?.aborted ?? false) {
        throw const OperationCanceled();
      }
      uploads[uploadId]!.$3[number] = List.of(body);
      return '"etag$number"';
    } finally {
      partsInFlight--;
    }
  }

  @override
  Future<void> completeMultipartUpload(String bucket, String key, String uploadId, List<S3Part> parts) async {
    _call('completeMultipartUpload');
    final upload = uploads.remove(uploadId)!;
    _bucket(bucket)[key] = [for (final part in parts) ...upload.$3[part.number]!];
  }

  @override
  Future<void> abortMultipartUpload(String bucket, String key, String uploadId) async {
    _call('abortMultipartUpload');
    uploads.remove(uploadId);
  }

  @override
  Future<void> copyObject(String fromBucket, String fromKey, String toBucket, String toKey) async {
    _call('copyObject');
    _bucket(toBucket)[toKey] = List.of(_bucket(fromBucket)[fromKey]!);
  }

  @override
  Future<String> uploadPartCopy(
    String fromBucket,
    String fromKey,
    String toBucket,
    String toKey,
    String uploadId,
    int number,
    int first,
    int last,
  ) async {
    _call('uploadPartCopy');
    return '"copy$number"';
  }

  @override
  Future<void> deleteObject(String bucket, String key) async {
    _call('deleteObject');
    _bucket(bucket).remove(key);
  }

  @override
  Future<List<S3DeleteFailure>> deleteObjects(String bucket, List<String> keys) async {
    _call('deleteObjects');
    if (noBatchDelete) {
      throw FsError(bucket, FsErrorKind.notSupported, const S3Failure(status: 501, code: 'NotImplemented'));
    }
    keys.forEach(_bucket(bucket).remove);
    return const [];
  }

  @override
  Future<void> createBucket(String bucket) async {
    _call('createBucket');
    _buckets[bucket] = {};
  }

  @override
  Future<void> deleteBucket(String bucket) async {
    _call('deleteBucket');
    _buckets.remove(bucket);
  }

  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}
