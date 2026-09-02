import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

/// Подставные секреты: отвечает заготовленным и записывает, о чём спрашивали.
///
/// Без неё тест модуля повис бы на первом же защищённом архиве: настоящая
/// служба ждёт ответа из окна, а окна в тесте провайдера нет.
class FakeCredentials extends ChangeNotifier implements Credentials {
  FakeCredentials({this.answers = const []});

  /// Что отвечать — по очереди, на каждый следующий вопрос.
  ///
  /// Список, а не одно значение, именно ради повторов: первый ответ неверный,
  /// второй подходит — так проверяется, что модуль спрашивает заново.
  /// Кончился — дальше пользователь «отказывается».
  final List<String?> answers;

  /// О чём спросили, по порядку.
  final List<CredentialRequest> asked = [];

  /// Что уже запомнено: адрес → ответ.
  final Map<String, Credential> known = {};

  @override
  Future<Credential?> obtain(CredentialRequest request) async {
    final remembered = known[request.realm];
    if (remembered != null) {
      return remembered;
    }

    asked.add(request);
    if (asked.length > answers.length) {
      return null;
    }

    final answer = answers[asked.length - 1];
    if (answer == null) {
      return null;
    }

    return known[request.realm] = Credential.password(answer);
  }

  @override
  void forget(String realm) => known.remove(realm);

  /// Окна в тестах нет, спрашивать некому.
  @override
  CredentialRequest? get pending => null;

  @override
  void answer(Credential? credential) {}
}
