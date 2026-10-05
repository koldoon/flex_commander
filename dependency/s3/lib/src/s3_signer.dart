import 'dart:convert';

import 'package:crypto/crypto.dart';

import 's3_encoding.dart';

/// Хеш пустого тела — у запросов без тела (`GET`, `HEAD`, `DELETE`, листинги).
const String emptyPayloadHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// Тело не хешируется: его целостность держит TLS (`docs/spec/s3.md`, §7).
const String unsignedPayload = 'UNSIGNED-PAYLOAD';

/// Что подписывается.
class SigningInput {
  const SigningInput({
    required this.method,
    required this.canonicalUri,
    this.query = const {},
    required this.headers,
    required this.payloadHash,
  });

  final String method;

  /// Путь — уже закодированный по правилу 1 (`/` — для корня).
  final String canonicalUri;

  /// Строка запроса — сырыми значениями: кодирует подпись сама (правило 2).
  final Map<String, String> query;

  /// Подписываемые заголовки, `host` в их числе. Имена — любого регистра.
  final Map<String, String> headers;

  /// `x-amz-content-sha256`: хеш тела, [emptyPayloadHash] или [unsignedPayload].
  final String payloadHash;
}

/// Подпись AWS Signature Version 4 — чистой функцией: время приходит снаружи.
///
/// Ради неё клиент и пишется своим (`docs/spec/s3.md`, §7): канонический
/// запрос, цепочка ключей по дате и подпись строки. Проверяется векторами из
/// документации AWS — ровно как разбор `MLSD` у FTP проверяется настоящими
/// строками сервера.
class SigV4Signer {
  SigV4Signer({required this.accessKey, required String secretKey, this.service = 's3'}) : _secret = secretKey;

  final String accessKey;
  final String _secret;
  final String service;

  /// Ключ подписи по (дата, регион): цепочка из четырёх HMAC одна на сутки.
  final Map<(String, String), List<int>> _keys = {};

  /// Сколько раз ключ считался — для проверки, что он помнится.
  int signingKeysComputed = 0;

  /// Канонический запрос: метод, путь, запрос, заголовки, их имена, хеш тела.
  String canonicalRequest(SigningInput input) {
    final headers = _canonicalHeaders(input.headers);
    return [
      input.method,
      input.canonicalUri.isEmpty ? '/' : input.canonicalUri,
      canonicalQuery(input.query),
      for (final entry in headers.entries) '${entry.key}:${entry.value}',
      '',
      headers.keys.join(';'),
      input.payloadHash,
    ].join('\n');
  }

  /// Строка для подписи.
  String stringToSign(String canonicalRequest, DateTime utc, String region) => [
    'AWS4-HMAC-SHA256',
    amzDate(utc),
    _scope(utc, region),
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');

  /// Ключ подписи на сутки и регион: `AWS4`+секрет → дата → регион → служба
  /// → `aws4_request`.
  List<int> signingKey(String yyyymmdd, String region) => _keys.putIfAbsent((yyyymmdd, region), () {
    signingKeysComputed++;
    var key = _hmac(utf8.encode('AWS4$_secret'), yyyymmdd);
    key = _hmac(key, region);
    key = _hmac(key, service);
    return _hmac(key, 'aws4_request');
  });

  /// Заголовки, которые надо добавить к запросу: `authorization` и
  /// `x-amz-date`. `x-amz-content-sha256` — уже среди подписываемых.
  Map<String, String> sign(SigningInput input, DateTime utc, String region) {
    final when = utc.toUtc();
    final withDate = {...input.headers, 'x-amz-date': amzDate(when)};
    final signed = SigningInput(
      method: input.method,
      canonicalUri: input.canonicalUri,
      query: input.query,
      headers: withDate,
      payloadHash: input.payloadHash,
    );
    final request = canonicalRequest(signed);
    final toSign = stringToSign(request, when, region);
    final signature = Hmac(sha256, signingKey(_day(when), region)).convert(utf8.encode(toSign)).toString();
    final names = _canonicalHeaders(withDate).keys.join(';');
    return {
      'authorization':
          'AWS4-HMAC-SHA256 Credential=$accessKey/${_scope(when, region)}, SignedHeaders=$names, Signature=$signature',
      'x-amz-date': amzDate(when),
    };
  }

  String _scope(DateTime utc, String region) => '${_day(utc)}/$region/$service/aws4_request';

  /// Заголовки по правилам: имя строчными, значение без краёв и со сжатыми
  /// внутренними пробелами, по имени по порядку.
  static Map<String, String> _canonicalHeaders(Map<String, String> headers) {
    final normal = <String, String>{
      for (final entry in headers.entries)
        entry.key.toLowerCase().trim(): entry.value.trim().replaceAll(RegExp(r'\s+'), ' '),
    };
    final names = normal.keys.toList()..sort();
    return {for (final name in names) name: normal[name]!};
  }

  static List<int> _hmac(List<int> key, String data) => Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  static String _day(DateTime utc) => '${utc.year.toString().padLeft(4, '0')}${_two(utc.month)}${_two(utc.day)}';

  /// `yyyyMMdd'T'HHmmss'Z'`.
  static String amzDate(DateTime utc) {
    final t = utc.toUtc();
    return '${_day(t)}T${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// SHA-256 тела шестнадцатеричной строкой.
String payloadHashOf(List<int> body) => sha256.convert(body).toString();

/// MD5 тела — для `Content-MD5` пачки удалений.
List<int> md5Of(List<int> body) => md5.convert(body).bytes;
