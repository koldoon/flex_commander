import 'dart:convert';

import 'package:fc_s3/fc_s3.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подпись SigV4 — векторами из документации AWS (`docs/spec/s3.md`, §7).
///
/// Числа — опубликованные, а не посчитанные нами: совпасть с ними случайно
/// нельзя, а значит и ошибиться в каноническом запросе незаметно тоже.
void main() {
  // Примеры «Signature Calculations for the Authorization Header: Single
  // Chunk» из руководства S3.
  final signer = SigV4Signer(accessKey: 'AKIAIOSFODNN7EXAMPLE', secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY');
  final when = DateTime.utc(2013, 5, 24);
  const host = 'examplebucket.s3.amazonaws.com';

  String signatureOf(Map<String, String> signed) => signed['authorization']!.split('Signature=').last;

  test('GET Object с Range', () {
    final input = SigningInput(
      method: 'GET',
      canonicalUri: '/test.txt',
      headers: {'host': host, 'range': 'bytes=0-9', 'x-amz-content-sha256': emptyPayloadHash},
      payloadHash: emptyPayloadHash,
    );

    final signed = signer.sign(input, when, 'us-east-1');

    expect(signatureOf(signed), 'f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41');
    expect(
      signed['authorization'],
      startsWith(
        'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, '
        'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, ',
      ),
    );
    expect(signed['x-amz-date'], '20130524T000000Z');
  });

  test('PUT Object: знак доллара в ключе, хеш тела, заголовок даты', () {
    final body = utf8.encode('Welcome to Amazon S3.');
    final hash = payloadHashOf(body);
    expect(hash, '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072');

    final input = SigningInput(
      method: 'PUT',
      canonicalUri: '/${encodeKeyPath(r'test$file.text')}',
      headers: {
        'host': host,
        'date': 'Fri, 24 May 2013 00:00:00 GMT',
        'x-amz-storage-class': 'REDUCED_REDUNDANCY',
        'x-amz-content-sha256': hash,
      },
      payloadHash: hash,
    );

    expect(
      signatureOf(signer.sign(input, when, 'us-east-1')),
      '98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd',
    );
  });

  test('GET ?lifecycle: ключ запроса без значения', () {
    final input = SigningInput(
      method: 'GET',
      canonicalUri: '/',
      query: const {'lifecycle': ''},
      headers: {'host': host, 'x-amz-content-sha256': emptyPayloadHash},
      payloadHash: emptyPayloadHash,
    );

    expect(
      signatureOf(signer.sign(input, when, 'us-east-1')),
      'fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543',
    );
  });

  test('GET Bucket ?max-keys=2&prefix=J: порядок ключей запроса', () {
    final input = SigningInput(
      method: 'GET',
      canonicalUri: '/',
      query: const {'prefix': 'J', 'max-keys': '2'},
      headers: {'host': host, 'x-amz-content-sha256': emptyPayloadHash},
      payloadHash: emptyPayloadHash,
    );

    expect(
      signatureOf(signer.sign(input, when, 'us-east-1')),
      '34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7',
    );
  });

  test('ключ подписи — пример из документации IAM', () {
    final iam = SigV4Signer(
      accessKey: 'AKIDEXAMPLE',
      secretKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
      service: 'iam',
    );

    final key = iam.signingKey('20120215', 'us-east-1');

    expect(
      key.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      'f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d',
    );
  });

  test('ключ подписи помнится на сутки и регион', () {
    final local = SigV4Signer(accessKey: 'a', secretKey: 'b');
    local.signingKey('20260101', 'us-east-1');
    local.signingKey('20260101', 'us-east-1');
    expect(local.signingKeysComputed, 1);

    local.signingKey('20260101', 'eu-west-1');
    local.signingKey('20260102', 'us-east-1');
    expect(local.signingKeysComputed, 3);
  });
}
