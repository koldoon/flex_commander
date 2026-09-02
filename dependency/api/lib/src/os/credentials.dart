import 'package:flutter/foundation.dart';

/// Что нужно спросить у пользователя и о чём.
///
/// Пароль к архиву и пароль к серверу — одна и та же задача: кто-то в глубине
/// (провайдер, фабрика) обнаруживает, что без секрета дальше нельзя, а спросить
/// может только тот, у кого есть экран. Разница между ними — в тексте вопроса.
@immutable
class CredentialRequest {
  const CredentialRequest({
    required this.realm,
    required this.title,
    required this.message,
    this.fields = const [CredentialField.password],
    this.retry = false,
  });

  /// Ключ, под которым ответ запоминается: `7z:/path/archive.7z`,
  /// `ssh:user@example.org`.
  ///
  /// Схема в начале не для красоты: один и тот же путь может значить разное для
  /// разных модулей, а перепутанный секрет — это лишний вопрос в лучшем случае.
  final String realm;

  /// Заголовок окна: «Encrypted archive», «SSH authentication».
  final String title;

  /// О чём спрашиваем: имя архива, адрес сервера.
  final String message;

  /// Что заполнять. Список, а не одна строка: серверу нужно и имя
  /// пользователя, и пароль.
  final List<CredentialField> fields;

  /// Прошлый ответ не подошёл — окно скажет об этом, а не спросит молча
  /// то же самое.
  final bool retry;

  /// Тот же запрос, но уже как повторный.
  CredentialRequest retrying() =>
      CredentialRequest(realm: realm, title: title, message: message, fields: fields, retry: true);

  @override
  String toString() => 'CredentialRequest($realm${retry ? ', повтор' : ''})';
}

/// Одно поле запроса.
@immutable
class CredentialField {
  const CredentialField({required this.name, required this.label, this.secret = false});

  /// Имя, по которому значение достают из ответа.
  final String name;

  final String label;

  /// Ввод скрыт точками, и значение не попадает ни в журнал, ни в заголовок.
  final bool secret;

  static const CredentialField password = CredentialField(name: 'password', label: 'Password', secret: true);
  static const CredentialField user = CredentialField(name: 'user', label: 'User name');
}

/// Ответ: значения по именам полей.
@immutable
class Credential {
  const Credential(this.values);

  /// Самый частый случай — один пароль.
  Credential.password(String password) : values = {CredentialField.password.name: password};

  final Map<String, String> values;

  String? operator [](String name) => values[name];

  String? get password => values[CredentialField.password.name];

  /// Секреты не печатаются: строка объекта попадает и в журнал, и в сообщение
  /// об ошибке.
  @override
  String toString() => 'Credential(${values.keys.join(', ')})';
}

/// Откуда берутся секреты.
///
/// Реализацию даёт ядро: спросить может только оно. Модуль получает службу так
/// же, как остальные, — через `services.resolve<Credentials>()` в своей фабрике.
///
/// **Повтор — забота спрашивающего**: только он знает, подошёл ли секрет.
/// Не подошедший забывается через [forget], и следующий [obtain] спросит заново:
///
/// ```dart
/// var request = CredentialRequest(realm: …, title: …, message: …);
/// while (true) {
///   final credential = await credentials.obtain(request);
///   if (credential == null) throw FsError(path, FsErrorKind.permissionDenied);
///   if (await tryOpen(credential.password)) break;
///   credentials.forget(request.realm);
///   request = request.retrying();
/// }
/// ```
/// Служба сама и спрашивает, и помнит ответ, поэтому [Listenable]: окно
/// вопроса рисует ядро, подписавшись на [pending]. Устройство то же, что у
/// [Toasts], — производитель зовёт `obtain`, а тот, у кого есть экран, следит
/// за тем, что нужно показать.
abstract interface class Credentials implements Listenable {
  /// Запомненное — или спрошенное, если запомненного нет.
  /// null — пользователь отказался отвечать.
  Future<Credential?> obtain(CredentialRequest request);

  /// Забыть запомненное для этого [CredentialRequest.realm].
  void forget(String realm);

  /// Запрос, на который сейчас ждут ответа; null — ничего не спрашивается.
  CredentialRequest? get pending;

  /// Ответ пользователя на [pending]; null — отказался.
  void answer(Credential? credential);
}
