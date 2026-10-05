import 'dart:typed_data';

import 's3_xml.dart';

/// Узкая граница между источником и протоколом (`docs/spec/s3.md`, §4).
///
/// Источник знает пути, каталоги и умения, а о HTTP, подписи и XML — ничего.
/// Наружу отсюда выходят только `FsError`: перевод кодов хранилища в общий вид
/// — дело того, кто их знает. Тесты источника работают на подставке.
abstract interface class S3Api {
  Future<List<S3Bucket>> listBuckets();

  /// Страница листинга. [delimiter] null — плоско, всё под префиксом
  /// (так удаляется поддерево).
  Future<S3Page> listObjects(
    String bucket, {
    String prefix = '',
    String? delimiter = '/',
    String? token,
    int maxKeys = 1000,
  });

  /// Сведения об объекте; null — такого нет.
  Future<S3Object?> headObject(String bucket, String key);

  /// Содержимое с [offset] (`Range`).
  Future<Stream<List<int>>> getObject(String bucket, String key, {int offset = 0});

  Future<void> putObject(String bucket, String key, Uint8List body, {S3Abort? abort});

  /// Начать многочастную загрузку; ответ — её номер.
  Future<String> createMultipartUpload(String bucket, String key);

  /// Часть загрузки; ответ — её ETag.
  Future<String> uploadPart(String bucket, String key, String uploadId, int number, Uint8List body, {S3Abort? abort});

  Future<void> completeMultipartUpload(String bucket, String key, String uploadId, List<S3Part> parts);

  /// Отменить загрузку. Уже отменённая — не ошибка.
  Future<void> abortMultipartUpload(String bucket, String key, String uploadId);

  /// Копия на стороне сервера — до 5 ГиБ.
  Future<void> copyObject(String fromBucket, String fromKey, String toBucket, String toKey);

  /// Часть многочастной копии — байты `[first, last]` источника; ответ — ETag.
  Future<String> uploadPartCopy(
    String fromBucket,
    String fromKey,
    String toBucket,
    String toKey,
    String uploadId,
    int number,
    int first,
    int last,
  );

  Future<void> deleteObject(String bucket, String key);

  /// Удалить пачкой, не больше тысячи. Хранилище без пачек (Google Storage) —
  /// `notSupported`, и тогда удаляют поштучно.
  Future<List<S3DeleteFailure>> deleteObjects(String bucket, List<String> keys);

  Future<void> createBucket(String bucket);

  Future<void> deleteBucket(String bucket);

  Future<void> close();
}

/// Обрыв запроса, который уже в полёте: отменённой загрузке незачем досылать
/// свои восемь мегабайт.
class S3Abort {
  final List<void Function()> _listeners = [];
  bool _aborted = false;

  bool get aborted => _aborted;

  void abort() {
    if (_aborted) {
      return;
    }
    _aborted = true;
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  /// Позвать [listener] при обрыве; уже оборвано — сразу.
  void onAbort(void Function() listener) {
    if (_aborted) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}
