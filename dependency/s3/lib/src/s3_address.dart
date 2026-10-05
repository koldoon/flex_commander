import 'package:fc_api/fc_api.dart';

/// Стиль адресации корзины: в пути (`host/bucket/key`) или поддоменом
/// (`bucket.host/key`).
enum S3Style { path, virtual }

/// Адрес хранилища: `s3[+http]://[КЛЮЧ[:СЕКРЕТ]@]хост[:порт][/корзина[/префикс]][?region=…&style=…]`
/// (`docs/spec/s3.md`, §5).
///
/// Соединение — в адресе, как у `ssh` и `ftp`: записей соединений в настройках
/// нет. Секрет, если его вписали в адрес, читается здесь **один раз** и дальше
/// не ходит — ни в путь, ни в realm, ни в ключ соединения.
class S3Target {
  S3Target._({
    required this.host,
    required this.port,
    required this.secure,
    required this.accessKey,
    required this.secretFromAddress,
    required this.bucket,
    required this.prefix,
    required this.regionOverride,
    required this.styleOverride,
  });

  /// HTTPS — по умолчанию.
  static const String scheme = 's3';

  /// Простой HTTP — для MinIO в своей сети. Отдельной схемой, а не флагом в
  /// запросе: транспорт выбирает человек и видит его в адресе, как `ftp` и
  /// `ftps`, — а флаг пропал бы, стоит отрезать хвост адреса.
  static const String plainScheme = 's3+http';

  factory S3Target.parse(Uri address) {
    if (address.host.isEmpty) {
      throw FsError(address.toString(), FsErrorKind.invalidAddress);
    }
    final secure = address.scheme != plainScheme;
    final info = address.userInfo;
    final colon = info.indexOf(':');
    final key = colon < 0 ? info : info.substring(0, colon);
    final secret = colon < 0 ? null : info.substring(colon + 1);
    final segments = [
      for (final segment in address.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    final query = address.queryParameters;
    final style = switch (query['style']) {
      'path' => S3Style.path,
      'virtual' => S3Style.virtual,
      _ => null,
    };
    final region = query['region'];
    return S3Target._(
      host: address.host,
      port: address.hasPort ? address.port : (secure ? 443 : 80),
      secure: secure,
      accessKey: key.isEmpty ? null : Uri.decodeComponent(key),
      secretFromAddress: secret == null || secret.isEmpty ? null : Uri.decodeComponent(secret),
      bucket: segments.isEmpty ? null : segments.first,
      prefix: segments.length < 2 ? '' : segments.skip(1).join('/'),
      regionOverride: region == null || region.isEmpty ? null : region,
      styleOverride: style,
    );
  }

  final String host;
  final int port;
  final bool secure;

  /// Идентификатор ключа доступа — на месте имени пользователя; регистр свой.
  final String? accessKey;

  /// Секрет из адреса: пробуется первым и ровно один раз.
  final String? secretFromAddress;

  /// Корзина из адреса; null — адрес называет только хранилище.
  final String? bucket;

  /// Префикс внутри корзины без краевых `/`; пусто — корень корзины.
  final String prefix;

  final String? regionOverride;
  final S3Style? styleOverride;

  String get schemeName => secure ? scheme : plainScheme;

  int get _defaultPort => secure ? 443 : 80;

  String get _hostPort => port == _defaultPort ? host : '$host:$port';

  /// Хранилище AWS — по хосту.
  bool get isAws => host == 'amazonaws.com' || host.endsWith('.amazonaws.com');

  /// Регион до первого ответа сервера: из запроса, из хоста AWS
  /// (`s3.<r>.amazonaws.com`, `s3-<r>.amazonaws.com`,
  /// `s3.dualstack.<r>.amazonaws.com`), иначе `us-east-1` — его понимают
  /// MinIO и Google Storage.
  String get initialRegion {
    if (regionOverride case final region?) {
      return region;
    }
    if (isAws) {
      final match = RegExp(r'^(?:[^.]+\.)*?s3[.-](?:dualstack\.)?([a-z0-9-]+)\.amazonaws\.com$').firstMatch(host);
      final found = match?.group(1);
      if (found != null && found != 'amazonaws' && found != 'external-1') {
        return found;
      }
    }
    return 'us-east-1';
  }

  /// Стиль для корзины: AWS — поддоменом, кроме имён с точкой по TLS
  /// (сертификат `*.s3.amazonaws.com` на них не сойдётся); всё прочее — в
  /// пути: MinIO на адресе-числе поддоменов не знает вовсе.
  S3Style styleFor(String bucket) =>
      styleOverride ?? (isAws && !(secure && bucket.contains('.')) ? S3Style.virtual : S3Style.path);

  /// Запрос адреса в постоянном виде: только свои ключи и в одном порядке —
  /// иначе один и тот же адрес давал бы два соединения.
  String get query => [
    if (regionOverride case final region?) 'region=${Uri.encodeQueryComponent(region)}',
    if (styleOverride case final style?) 'style=${style.name}',
  ].join('&');

  /// `//КЛЮЧ@хост[:порт]` — без секрета; стандартный порт не пишется.
  String get authority => '//${accessKey == null ? '' : '${Uri.encodeComponent(accessKey!)}@'}$_hostPort';

  /// Чем спрашивать секрет: у каждой пары схема—ключ—хост свой ответ.
  String get realm => '$schemeName:${accessKey ?? ''}@$host:$port';

  /// Как называть хранилище человеку: `КЛЮЧ@хост[:порт]`.
  String get display => '${accessKey == null ? '' : '$accessKey@'}$_hostPort';

  /// Путь внутри хранилища из пути панели: `//КЛЮЧ@хост:9000/b/k?region=x` →
  /// `/b/k`.
  ///
  /// Запрос снимается **только свой** — тот, что источник сам приписал: ключ с
  /// `?` внутри имени иначе обрезался бы на полуслове.
  String stripAuthorityAndQuery(String raw) {
    var path = raw;
    final own = query;
    if (own.isNotEmpty && path.endsWith('?$own')) {
      path = path.substring(0, path.length - own.length - 1);
    }
    if (path.startsWith('//')) {
      final slash = path.indexOf('/', 2);
      path = slash < 0 ? '/' : path.substring(slash);
    }
    return path.isEmpty ? '/' : path;
  }

  /// Хост и путь запроса к корзине — по стилю и региону.
  ///
  /// [encodedKey] — ключ, уже закодированный по правилу пути. У AWS хост
  /// региональный; у прочих — тот, что в адресе.
  ({String hostPort, String path}) endpoint({String? bucket, String encodedKey = '', required String region}) {
    if (bucket == null) {
      return (hostPort: _hostPort, path: '/');
    }
    final key = encodedKey.isEmpty ? '' : '/$encodedKey';
    final awsHost = region == initialRegion && !_isGlobalAws ? host : 's3.$region.amazonaws.com';
    final base = isAws ? awsHost : host;
    final hostPort = port == _defaultPort ? base : '$base:$port';
    return switch (styleFor(bucket)) {
      S3Style.virtual => (hostPort: '$bucket.$hostPort', path: key.isEmpty ? '/' : key),
      S3Style.path => (hostPort: hostPort, path: '/${Uri.encodeComponent(bucket)}$key'),
    };
  }

  /// Общий хост AWS (`s3.amazonaws.com`) — без региона: ответ направит.
  bool get _isGlobalAws => host == 's3.amazonaws.com';
}
