/// Разобранный адрес сервера: `ftp://user@host:2121/pub`.
///
/// Адрес приходит один раз — из строки, которую набрал человек, — и дальше
/// живёт только в этом виде: провайдер собирает из него путь, подключение берёт
/// имя и порт, а окно пароля — имя области. Устроен так же, как `SshTarget`,
/// и отличается ровно тем, чем отличаются протоколы.
class FtpTarget {
  FtpTarget({
    required this.host,
    String? user,
    int? port,
    this.path = '',
    this.secure = false,
    this.passwordFromAddress,
  }) : user = (user == null || user.isEmpty) ? anonymous : user,
       port = port ?? defaultPort;

  /// Порт по умолчанию. В путь он не пишется — иначе один и тот же сервер
  /// выглядел бы по-разному в зависимости от того, как его набрали.
  static const int defaultPort = 21;

  /// Имя анонимного входа — то, чем FTP отличается от ssh.
  ///
  /// Нет пользователя в адресе — значит `anonymous`, а не «под собой»:
  /// учётных записей чужого сервера у нас нет, а анонимный вход есть у
  /// половины публичных зеркал. Спрашивать пароль там, где сервер и так
  /// пускает всех, незачем (`docs/spec/ftp.md`, §11).
  static const String anonymous = 'anonymous';

  /// Пароль анонимного входа: по обычаю — почтовый адрес, и сервер его
  /// просит именно так («send your complete email address as your password»).
  static const String anonymousPassword = 'flex@commander';

  /// Схемы, которыми открывается этот источник.
  static const String scheme = 'ftp';
  static const String secureScheme = 'ftps';

  /// Разбирает `ftp://user:password@host:port/path` и `ftps://…`.
  factory FtpTarget.parse(Uri address) {
    final info = address.userInfo.split(':');
    return FtpTarget(
      host: address.host,
      user: info.first.isNotEmpty ? Uri.decodeComponent(info.first) : null,
      port: address.hasPort ? address.port : null,
      path: address.path,
      secure: address.scheme.toLowerCase() == secureScheme,
      // Пароль из адреса берётся здесь и больше нигде не появляется: в путь
      // идёт только [authority], иначе секрет уехал бы в settings.json вместе
      // с путём панели (`providers.md`, §5.6).
      passwordFromAddress: info.length > 1 && info[1].isNotEmpty ? Uri.decodeComponent(info[1]) : null,
    );
  }

  final String user;
  final String host;
  final int port;

  /// Путь на сервере из самого адреса; пустой — открыть то, куда сервер
  /// поставил нас сам.
  final String path;

  /// Шифровать ли соединение: `ftps://` — да, `ftp://` — нет.
  ///
  /// Схемой, а не догадкой по ответу `FEAT`: сервер из разведки объявляет
  /// `AUTH TLS` и тут же от него отказывается, так что «попробуем, вдруг
  /// выйдет» означало бы молчаливый откат к открытому паролю
  /// (`docs/spec/ftp.md`, §3.2).
  final bool secure;

  /// Пароль, набранный прямо в адресе. Используется один раз, при подключении.
  final String? passwordFromAddress;

  /// Анонимный ли это вход — тот, о котором не надо спрашивать.
  bool get isAnonymous => user == anonymous;

  /// Начало пути внутри провайдера: `//user@host` или `//user@host:2121`.
  String get authority => port == defaultPort ? '//$user@$host' : '//$user@$host:$port';

  /// Область, под которой помнится секрет: одно соединение — один ответ.
  String get realm => '${secure ? secureScheme : scheme}:$user@$host:$port';

  /// Как сервер называется в окне вопроса и в сообщении об ошибке.
  String get display => port == defaultPort ? '$user@$host' : '$user@$host:$port';

  /// Путь внутри провайдера без [authority]: `//user@host/pub` → `/pub`.
  ///
  /// Обе формы приходят по-настоящему: с началом — из сохранённого пути
  /// панели, без него — из ходьбы по дереву.
  String stripAuthority(String path) {
    if (!path.startsWith('//')) {
      return path;
    }
    final slash = path.indexOf('/', 2);
    return slash < 0 ? '/' : path.substring(slash);
  }

  @override
  String toString() => display;
}
