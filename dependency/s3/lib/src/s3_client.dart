import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';

import 's3_address.dart';
import 's3_api.dart';
import 's3_encoding.dart';
import 's3_errors.dart';
import 's3_signer.dart';
import 's3_xml.dart';

/// Клиент S3 на `dart:io` (`docs/spec/s3.md`, §4).
///
/// Свой, а не пакет: готовые держат объект в памяти целиком или не умеют
/// читать потоком. Здесь — подпись каждого запроса, исправление региона и
/// часов по ответу сервера, повторы на перегрузку и перевод ответов в
/// `FsError`.
class S3Client implements S3Api {
  S3Client(
    this.target, {
    required String accessKey,
    required String secretKey,
    HttpClient? http,
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? sleep,
  }) : _signer = SigV4Signer(accessKey: accessKey, secretKey: secretKey),
       _http = http ?? _defaultHttp(),
       _clock = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  final S3Target target;
  final SigV4Signer _signer;
  final HttpClient _http;
  final DateTime Function() _clock;
  final Future<void> Function(Duration delay) _sleep;

  /// Регион корзины, узнанный из ответа сервера.
  final Map<String, String> _regions = {};

  /// Насколько часы сервера впереди наших — узнаётся из `RequestTimeTooSkewed`.
  Duration _skew = Duration.zero;

  /// Сколько раз пробовать запрос, который можно повторить.
  static const int attempts = 4;

  /// Сколько ждать заголовков ответа. Итог многочастной загрузки и копия
  /// бывают долгими: сервер собирает объект, а то и копирует гигабайты.
  static const Duration headerTimeout = Duration(seconds: 60);
  static const Duration longTimeout = Duration(minutes: 10);

  /// Сколько тело чтения вправе молчать.
  static const Duration bodyIdle = Duration(seconds: 60);

  static HttpClient _defaultHttp() =>
      HttpClient()
        // Напрямую, как ssh и ftp: `HttpClient` молча берёт прокси из окружения
        // (`HTTP_PROXY`), и запущенное из терминала приложение ходило бы к MinIO
        // в своей сети через чужой прокси — и висело. Живая проверка это и
        // поймала (`docs/spec/s3.md`, §17).
        ..findProxy = ((_) => 'DIRECT')
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 15)
        ..maxConnectionsPerHost = 16
        // Сжатие — мимо: объект, лежащий сжатым, приехал бы распакованным, и `Range`
        // считал бы не те байты.
        ..autoUncompress = false
        ..userAgent = 'FlexCommander';

  // --- запрос ---

  Future<HttpClientResponse> _send(
    String method, {
    String? bucket,
    String key = '',
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    Uint8List? body,
    bool hashBody = false,
    S3Abort? abort,
    Duration timeout = headerTimeout,
    bool okOnMissing = false,
  }) async {
    var regionFixed = false;
    var clockFixed = false;
    for (var attempt = 1; ; attempt++) {
      final region = bucket == null ? target.initialRegion : (_regions[bucket] ?? target.initialRegion);
      final encodedKey = encodeKeyPath(key);
      final where = target.endpoint(bucket: bucket, encodedKey: encodedKey, region: region);
      final q = canonicalQuery(query);
      final uri = Uri.parse(
        '${target.secure ? 'https' : 'http'}://${where.hostPort}${where.path}${q.isEmpty ? '' : '?$q'}',
      );
      if (uri.path != where.path) {
        // `Uri` выбросил сегмент `.` или `..` — такой ключ ушёл бы чужим.
        throw FsError(key, FsErrorKind.invalidName);
      }

      // Тело хешируется только маленькое (XML): содержимое файлов идёт без
      // хеша — его целостность держит TLS, а MinIO такое тело принимает и по
      // простому HTTP (разведка §3).
      final payload =
          body == null || body.isEmpty ? emptyPayloadHash : (hashBody ? payloadHashOf(body) : unsignedPayload);
      final signedHeaders = {'host': where.hostPort, 'x-amz-content-sha256': payload, ...headers};
      final signature = _signer.sign(
        SigningInput(
          method: method,
          canonicalUri: where.path,
          query: query,
          headers: signedHeaders,
          payloadHash: payload,
        ),
        _clock().toUtc().add(_skew),
        region,
      );

      HttpClientResponse response;
      try {
        final request = await _http.openUrl(method, uri);
        abort?.onAbort(() => request.abort(const OperationCanceled()));
        request.headers.removeAll(HttpHeaders.acceptEncodingHeader);
        for (final entry in {...signedHeaders, ...signature}.entries) {
          if (entry.key != 'host') {
            request.headers.set(entry.key, entry.value);
          }
        }
        request.contentLength = body?.length ?? 0;
        if (body != null && body.isNotEmpty) {
          request.add(body);
        }
        response = await request.close().timeout(timeout);
      } on OperationCanceled {
        rethrow;
      } on Object catch (error) {
        if (abort?.aborted ?? false) {
          throw const OperationCanceled();
        }
        if (attempt < attempts && _retryableError(error)) {
          await _sleep(_backoff(attempt));
          continue;
        }
        throw _connectionError(error);
      }

      final status = response.statusCode;
      if (status < 300 || (okOnMissing && status == 404)) {
        return response;
      }

      final text = await _readBody(response);
      final error = parseError(text);
      final failure = S3Failure(
        status: status,
        code: error?.code ?? (status == 404 ? 'NoSuchKey' : '$status'),
        message: error?.message ?? '',
        requestId: response.headers.value('x-amz-request-id'),
      );

      // Не тот регион: сервер называет нужный — повторить один раз.
      final named = response.headers.value('x-amz-bucket-region') ?? error?.region;
      if (bucket != null && !regionFixed && named != null && named.isNotEmpty && named != region) {
        _regions[bucket] = named;
        regionFixed = true;
        continue;
      }
      // Часы разошлись: взять время сервера — и повторить один раз.
      if (failure.code == 'RequestTimeTooSkewed' && !clockFixed) {
        final date = response.headers.value(HttpHeaders.dateHeader);
        if (date != null) {
          _skew = HttpDate.parse(date).difference(_clock().toUtc());
          clockFixed = true;
          continue;
        }
      }
      if (attempt < attempts && _retryableStatus(failure)) {
        await _sleep(_backoff(attempt));
        continue;
      }
      throw s3Error(key.isEmpty ? (bucket ?? target.display) : '$bucket/$key', failure);
    }
  }

  static bool _retryableStatus(S3Failure failure) =>
      failure.status >= 500 || const {'SlowDown', 'InternalError', 'RequestTimeout'}.contains(failure.code);

  static bool _retryableError(Object error) =>
      error is SocketException || error is TimeoutException || error is HttpException;

  /// Ожидание перед повтором: 200 мс, удваиваясь, с разбросом в пятую часть.
  Duration _backoff(int attempt) {
    final base = 200 * math.pow(2, attempt - 1);
    final jitter = 1 + (math.Random().nextDouble() - 0.5) * 0.4;
    return Duration(milliseconds: (base * jitter).round());
  }

  /// Не достучались — это не «ошибка ввода-вывода», а «не подключиться»
  /// (`ftp.md`, §10а).
  FsError _connectionError(Object error) => FsError(target.display, FsErrorKind.cannotConnect, error);

  static Future<String> _readBody(HttpClientResponse response) async {
    try {
      return await utf8.decodeStream(response).timeout(bodyIdle);
    } on Object {
      return '';
    }
  }

  Future<String> _text(HttpClientResponse response) => _readBody(response);

  /// Ответ 200 с ошибкой внутри — так отвечают итог многочастной загрузки и
  /// копия: заголовки уходят сразу, а исход — уже в теле.
  void _throwIfError(String text, String path) {
    final error = parseError(text);
    if (error != null) {
      throw s3Error(path, S3Failure(status: 200, code: error.code, message: error.message));
    }
  }

  // --- S3Api ---

  @override
  Future<List<S3Bucket>> listBuckets() async => parseBuckets(await _text(await _send('GET')));

  @override
  Future<S3Page> listObjects(
    String bucket, {
    String prefix = '',
    String? delimiter = '/',
    String? token,
    int maxKeys = 1000,
  }) async {
    final response = await _send(
      'GET',
      bucket: bucket,
      query: {
        'list-type': '2',
        'encoding-type': 'url',
        'max-keys': '$maxKeys',
        if (prefix.isNotEmpty) 'prefix': prefix,
        if (delimiter != null) 'delimiter': delimiter,
        if (token != null) 'continuation-token': token,
      },
    );
    return parseListV2(await _text(response));
  }

  @override
  Future<S3Object?> headObject(String bucket, String key) async {
    final response = await _send('HEAD', bucket: bucket, key: key, okOnMissing: true);
    await response.drain<void>();
    if (response.statusCode == 404) {
      return null;
    }
    final modified = response.headers.value(HttpHeaders.lastModifiedHeader);
    return S3Object(
      key: key,
      size: response.contentLength < 0 ? 0 : response.contentLength,
      modified: modified == null ? null : HttpDate.parse(modified),
      etag: response.headers.value(HttpHeaders.etagHeader),
    );
  }

  @override
  Future<Stream<List<int>>> getObject(String bucket, String key, {int offset = 0}) async {
    final response = await _send('GET', bucket: bucket, key: key, headers: {if (offset > 0) 'range': 'bytes=$offset-'});
    final path = '$bucket/$key';
    return response
        .timeout(bodyIdle)
        .handleError((Object error) => throw error is FsError ? error : FsError(path, FsErrorKind.io, error));
  }

  @override
  Future<void> putObject(String bucket, String key, Uint8List body, {S3Abort? abort}) async {
    final response = await _send('PUT', bucket: bucket, key: key, body: body, abort: abort);
    await response.drain<void>();
  }

  @override
  Future<String> createMultipartUpload(String bucket, String key) async {
    final response = await _send('POST', bucket: bucket, key: key, query: const {'uploads': ''});
    return parseUploadId(await _text(response));
  }

  @override
  Future<String> uploadPart(
    String bucket,
    String key,
    String uploadId,
    int number,
    Uint8List body, {
    S3Abort? abort,
  }) async {
    final response = await _send(
      'PUT',
      bucket: bucket,
      key: key,
      query: {'partNumber': '$number', 'uploadId': uploadId},
      body: body,
      abort: abort,
    );
    await response.drain<void>();
    return response.headers.value(HttpHeaders.etagHeader) ?? '';
  }

  @override
  Future<void> completeMultipartUpload(String bucket, String key, String uploadId, List<S3Part> parts) async {
    final response = await _send(
      'POST',
      bucket: bucket,
      key: key,
      query: {'uploadId': uploadId},
      body: Uint8List.fromList(utf8.encode(completeXml(parts))),
      hashBody: true,
      timeout: longTimeout,
    );
    _throwIfError(await _text(response), '$bucket/$key');
  }

  @override
  Future<void> abortMultipartUpload(String bucket, String key, String uploadId) async {
    try {
      final response = await _send('DELETE', bucket: bucket, key: key, query: {'uploadId': uploadId});
      await response.drain<void>();
    } on FsError catch (error) {
      // Уже отменённая — не ошибка.
      if (error.kind != FsErrorKind.notFound) {
        rethrow;
      }
    }
  }

  @override
  Future<void> copyObject(String fromBucket, String fromKey, String toBucket, String toKey) async {
    final response = await _send(
      'PUT',
      bucket: toBucket,
      key: toKey,
      headers: {'x-amz-copy-source': copySource(fromBucket, fromKey)},
      timeout: longTimeout,
    );
    _throwIfError(await _text(response), '$toBucket/$toKey');
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
    final response = await _send(
      'PUT',
      bucket: toBucket,
      key: toKey,
      query: {'partNumber': '$number', 'uploadId': uploadId},
      headers: {'x-amz-copy-source': copySource(fromBucket, fromKey), 'x-amz-copy-source-range': 'bytes=$first-$last'},
      timeout: longTimeout,
    );
    final text = await _text(response);
    _throwIfError(text, '$toBucket/$toKey');
    return RegExp(
          r'<ETag>(.*?)</ETag>',
        ).firstMatch(text)?.group(1)?.replaceAll('&#34;', '"').replaceAll('&quot;', '"') ??
        '';
  }

  @override
  Future<void> deleteObject(String bucket, String key) async {
    final response = await _send('DELETE', bucket: bucket, key: key);
    await response.drain<void>();
  }

  @override
  Future<List<S3DeleteFailure>> deleteObjects(String bucket, List<String> keys) async {
    final body = Uint8List.fromList(utf8.encode(deleteXml(keys)));
    final response = await _send(
      'POST',
      bucket: bucket,
      query: const {'delete': ''},
      // Пачка требует `Content-MD5` у AWS; MinIO и прочие его понимают.
      headers: {'content-md5': base64.encode(md5Of(body))},
      body: body,
      hashBody: true,
    );
    return parseDeleteResult(await _text(response));
  }

  @override
  Future<void> createBucket(String bucket) async {
    final response = await _send('PUT', bucket: bucket);
    await response.drain<void>();
  }

  @override
  Future<void> deleteBucket(String bucket) async {
    final response = await _send('DELETE', bucket: bucket);
    await response.drain<void>();
  }

  @override
  Future<void> close() async => _http.close(force: true);
}
