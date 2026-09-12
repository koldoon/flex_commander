import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_updater/fc_updater.dart';
import 'package:flutter_test/flutter_test.dart';

/// Загрузка выпуска и сверка суммы — на своём же сервере, без интернета
/// (`docs/spec/self-update.md`, §4).
void main() {
  late HttpServer server;
  late Directory cache;
  late List<int> payload;

  /// Сколько раз у сервера просили файл: по этому видно, что отменённая
  /// загрузка не повторяется сама собой.
  var requests = 0;

  setUp(() async {
    payload = utf8.encode('содержимое выпуска' * 64);
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      if (request.uri.path == '/missing') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..contentLength = payload.length
        ..add(payload);
      await request.response.close();
    });
    cache = await Directory.systemTemp.createTemp('fc_updates');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await cache.exists()) {
      await cache.delete(recursive: true);
    }
  });

  ReleaseAsset asset({String? sum, String path = '/release.zip'}) => ReleaseAsset(
    name: 'flex_commander-v0.0.73-macos-arm64.zip',
    url: 'http://${server.address.address}:${server.port}$path',
    sha256: sum ?? sha256.convert(payload).toString(),
    size: payload.length,
  );

  test('скачанное с верной суммой ложится в кеш', () async {
    final progress = <int>[];
    final file = await UpdateDownload(into: cache).fetch(asset(), onProgress: (received, _) => progress.add(received));

    expect(await file.exists(), isTrue);
    expect(await file.length(), payload.length);
    expect(file.path, contains('flex_commander-v0.0.73-macos-arm64.zip'));
    expect(progress, isNotEmpty, reason: 'ход загрузки — то, чем живёт полоска работы');
    expect(progress.last, payload.length);
  });

  test('сумма не сошлась — скачанное выброшено', () async {
    final download = UpdateDownload(into: cache);

    await expectLater(
      download.fetch(asset(sum: 'f' * 64)),
      throwsA(isA<FsError>()),
      reason: 'подменённый файл ставить нельзя',
    );

    // В кеше не остаётся ни целого файла, ни его остатка: следующая попытка
    // не должна принять чужое за своё.
    expect(cache.listSync(), isEmpty);
  });

  test('файла нет на сервере — это «не дозвонились», а не «сумма не та»', () async {
    await expectLater(
      UpdateDownload(into: cache).fetch(asset(path: '/missing')),
      throwsA(isA<FsError>().having((error) => error.kind, 'вид', FsErrorKind.cannotConnect)),
    );
  });

  test('файл без названной суммы не качается вовсе', () async {
    await expectLater(
      UpdateDownload(into: cache).fetch(asset(sum: '')),
      throwsA(isA<FsError>().having((error) => error.kind, 'вид', FsErrorKind.notSupported)),
    );
    expect(requests, 0, reason: 'качать непроверяемое незачем — даже начинать');
  });

  test('отмена прекращает загрузку и не оставляет следов', () async {
    await expectLater(
      UpdateDownload(into: cache).fetch(asset(), canceled: () => true),
      throwsA(isA<OperationCanceled>()),
    );
    expect(cache.listSync(), isEmpty);
  });
}
