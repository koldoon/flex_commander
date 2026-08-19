import 'dart:io';

/// Разобранный адрес сервера: `ssh://user@host:2222/srv`.
///
/// Адрес приходит один раз — из строки, которую набрал человек, — и дальше
/// живёт только в этом виде: провайдер собирает из него путь, подключение берёт
/// имя и порт, а окно пароля — имя области.
class SshTarget {
  SshTarget({required this.user, required this.host, int? port, this.path = '', this.passwordFromAddress})
    : port = port ?? defaultPort;

  /// Порт по умолчанию. В путь он не пишется — иначе один и тот же сервер
  /// выглядел бы по-разному в зависимости от того, как его набрали.
  static const int defaultPort = 22;

  /// Разбирает `ssh://user:password@host:port/path`.
  ///
  /// Имени пользователя может не быть: `ssh://host/srv` значит «под собой»,
  /// как и `ssh host` в терминале.
  factory SshTarget.parse(Uri address) {
    final info = address.userInfo.split(':');
    final user = info.first.isNotEmpty ? info.first : _currentUser();
    return SshTarget(
      user: user,
      host: address.host,
      port: address.hasPort ? address.port : null,
      path: address.path,
      // Пароль из адреса берётся здесь и больше нигде не появляется: в путь
      // идёт только [authority], иначе секрет уехал бы в settings.json вместе
      // с путём панели.
      passwordFromAddress: info.length > 1 && info[1].isNotEmpty ? Uri.decodeComponent(info[1]) : null,
    );
  }

  final String user;
  final String host;
  final int port;

  /// Путь на сервере из самого адреса; пустой — открыть дом пользователя.
  final String path;

  /// Пароль, набранный прямо в адресе. Используется один раз, при подключении.
  final String? passwordFromAddress;

  /// Начало пути внутри провайдера: `//user@host` или `//user@host:2222`.
  ///
  /// Двоеточие в имени схемы уже съедено разбором пути, а здесь оно
  /// разделяет хост и порт — [NodePath] режет строку по двоеточиям, но
  /// схемой считает только то, что не содержит `/`, так что `//user@host:2222`
  /// остаётся одним куском.
  String get authority => port == defaultPort ? '//$user@$host' : '//$user@$host:$port';

  /// Область, под которой помнится секрет: одно соединение — один ответ.
  String get realm => 'ssh:$user@$host:$port';

  /// Как сервер называется в окне вопроса и в сообщении об ошибке.
  String get display => port == defaultPort ? '$user@$host' : '$user@$host:$port';

  /// Путь внутри провайдера без [authority]: `//user@host/srv` → `/srv`.
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

  static String _currentUser() {
    final env = Platform.environment;
    return env['USER'] ?? env['LOGNAME'] ?? '';
  }
}
