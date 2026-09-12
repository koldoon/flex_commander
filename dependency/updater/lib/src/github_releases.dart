import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';

import 'app_version.dart';
import 'release.dart';

/// Выпуски проекта на GitHub — открытым API, без ключа доступа.
///
/// Репозиторий открытый, предел безымянных запросов — шестьдесят в час; при
/// одной проверке в сутки этого хватает с запасом
/// (`docs/spec/self-update.md`, §3).
class GithubReleases implements ReleaseSource {
  GithubReleases({required this.repository, HttpClient? client, this.timeout = const Duration(seconds: 15)})
    : _client = client;

  /// `koldoon/flex_commander` — тот же репозиторий, из которого собрано
  /// приложение.
  final String repository;

  final Duration timeout;

  final HttpClient? _client;

  Uri get _latest => Uri.https('api.github.com', '/repos/$repository/releases/latest');

  @override
  Future<ReleaseInfo?> latest() async {
    final client = _client ?? HttpClient();
    client.connectionTimeout = timeout;
    try {
      final request = await client.getUrl(_latest).timeout(timeout);
      // Без этого GitHub отвечает своим «по умолчанию», а не тем, о чём
      // договаривались: заголовок версии API — часть договора.
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      // Своё имя называют все клиенты API, и GitHub требует этого прямо.
      request.headers.set(HttpHeaders.userAgentHeader, 'flex-commander-updater');

      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      // «Выпусков нет» — это не беда: у нового репозитория их и не бывает.
      if (response.statusCode == HttpStatus.notFound) {
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        // Предел запросов, отказ сети, чужая ошибка — для человека это одно:
        // спросить не вышло. Разницу видно в журнале, не в окне.
        throw FsError(_latest.host, FsErrorKind.cannotConnect);
      }

      return parse(body);
    } on SocketException catch (error) {
      throw FsError(_latest.host, FsErrorKind.cannotConnect, error);
    } on HttpException catch (error) {
      throw FsError(_latest.host, FsErrorKind.cannotConnect, error);
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  /// Разбирает ответ API.
  ///
  /// Отдельно от запроса — и проверяется отдельно: ответ живого сервера в
  /// тесте не нужен, а вот его форма нужна очень.
  static ReleaseInfo? parse(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final tag = decoded['tag_name'];
    if (tag is! String) {
      return null;
    }
    final version = AppVersion.parse(tag);
    if (version == null) {
      return null;
    }

    final assets = <ReleaseAsset>[];
    final listed = decoded['assets'];
    if (listed is List) {
      for (final entry in listed) {
        if (entry is! Map) {
          continue;
        }
        final name = entry['name'];
        final url = entry['browser_download_url'];
        if (name is! String || url is! String) {
          continue;
        }
        // `digest` приходит с приставкой протокола — `sha256:f34bfe…`. Чужую
        // приставку не берём вовсе: сверять ею всё равно нечем.
        final digest = entry['digest'];
        final sum = digest is String && digest.startsWith('sha256:') ? digest.substring('sha256:'.length) : '';
        final size = entry['size'];
        assets.add(ReleaseAsset(name: name, url: url, sha256: sum, size: size is int ? size : 0));
      }
    }

    final notes = decoded['body'];
    return ReleaseInfo(version: version, tag: tag, notes: notes is String ? notes : '', assets: assets);
  }
}
