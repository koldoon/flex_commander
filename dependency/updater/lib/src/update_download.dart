import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fc_api/fc_api.dart';

import 'release.dart';

/// Загрузка файла выпуска с проверкой суммы.
///
/// Сумму называет GitHub (`digest`), и сверяется она **до** того, как что-то
/// подменять: не сошлась — скачанное выбрасывается
/// (`docs/spec/self-update.md`, §4).
class UpdateDownload {
  UpdateDownload({required this.into, HttpClient? client, this.timeout = const Duration(seconds: 30)})
    : _client = client;

  /// Куда складывать скачанное — обычно каталог кеша приложения.
  final Directory into;

  final Duration timeout;

  final HttpClient? _client;

  /// Качает файл и возвращает его.
  ///
  /// [onProgress] — сколько байт из скольких уже пришло; по нему рисуется
  /// полоска работы. [canceled] — способ прерваться: работа отменяемая, и
  /// ждать конца загрузки, чтобы узнать об отмене, незачем.
  Future<File> fetch(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    bool Function()? canceled,
  }) async {
    if (asset.sha256.isEmpty) {
      // Ставить непроверяемое нельзя — а качать его тем более незачем.
      throw FsError(asset.name, FsErrorKind.notSupported);
    }

    await into.create(recursive: true);
    // Имя с суммой: два выпуска с одинаковым именем файла — обычное дело, а
    // недокачанный остаток от прошлого раза не должен сойти за целый.
    final file = File('${into.path}/${asset.sha256.substring(0, 12)}-${asset.name}');
    final partial = File('${file.path}.part');

    final client = _client ?? HttpClient();
    client.connectionTimeout = timeout;
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(asset.url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'flex-commander-updater');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw FsError(asset.name, FsErrorKind.cannotConnect);
      }

      final total = response.contentLength > 0 ? response.contentLength : asset.size;
      var received = 0;
      sink = partial.openWrite();
      await for (final chunk in response) {
        if (canceled?.call() ?? false) {
          throw const OperationCanceled();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final sum = await _sha256Of(partial);
      if (sum != asset.sha256.toLowerCase()) {
        await partial.delete();
        // Своя беда, а не сетевая: файл пришёл целиком, но это не тот файл.
        throw FsError(asset.name, FsErrorKind.invalidName);
      }

      if (await file.exists()) {
        await file.delete();
      }
      await partial.rename(file.path);
      return file;
    } on SocketException catch (error) {
      throw FsError(asset.name, FsErrorKind.cannotConnect, error);
    } finally {
      await sink?.close();
      if (await partial.exists()) {
        await partial.delete();
      }
      if (_client == null) {
        client.close();
      }
    }
  }

  /// Сумма файла — по частям, а не целиком в памяти: двадцать четыре мегабайта
  /// держать в куче незачем.
  static Future<String> _sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
