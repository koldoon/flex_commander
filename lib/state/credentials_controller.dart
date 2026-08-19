import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Реализация [Credentials]: память на время работы и окно вопроса.
///
/// **Пароли никуда не пишутся.** Ни в настройки, ни во временные файлы: они
/// живут в этой карте и исчезают вместе с процессом. Связка ключей появится
/// отдельной реализацией — модулям для этого меняться не придётся.
class CredentialsController extends ChangeNotifier implements Credentials {
  final Map<String, Credential> _known = {};

  CredentialRequest? _pending;
  Completer<Credential?>? _answer;

  @override
  CredentialRequest? get pending => _pending;

  @override
  Future<Credential?> obtain(CredentialRequest request) {
    final known = _known[request.realm];
    if (known != null) {
      // Спрашивать заново незачем: 7z запускает программу на каждое чтение
      // записи, и без памяти окно появлялось бы на каждый файл.
      return Future.value(known);
    }

    // Второй вопрос поверх первого приложение задать не может: окно модальное.
    // Но спросить могут двое сразу — обе панели открывают один архив, — и тогда
    // второй ждёт того же ответа, а не своей очереди.
    final waiting = _answer;
    if (waiting != null && _pending?.realm == request.realm) {
      return waiting.future;
    }

    _pending = request;
    final answer = _answer = Completer<Credential?>();
    notifyListeners();
    return answer.future;
  }

  /// Ответ пользователя; null — отказался.
  @override
  void answer(Credential? credential) {
    final waiting = _answer;
    final request = _pending;
    if (waiting == null || request == null) {
      return;
    }

    if (credential != null) {
      _known[request.realm] = credential;
    }

    _pending = null;
    _answer = null;
    waiting.complete(credential);
    notifyListeners();
  }

  @override
  void forget(String realm) => _known.remove(realm);

  /// Помнит ли что-то про этот адрес. Нужно проверкам и отладке; сам секрет
  /// наружу не отдаётся.
  bool knows(String realm) => _known.containsKey(realm);

  @override
  void dispose() {
    // Незаконченный вопрос закрывается отказом: иначе тот, кто ждёт ответа,
    // остался бы висеть навсегда.
    _answer?.complete(null);
    _answer = null;
    _pending = null;
    _known.clear();
    super.dispose();
  }
}
