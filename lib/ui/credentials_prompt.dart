import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Окно вопроса о секрете — экранная половина [Credentials].
///
/// Спрашивает ядро: секрет нужен тому, кто работает с источником. Здесь только
/// показ и ответ — и ни одного запомненного пароля: помнит их та сторона, где
/// спрашивают (`docs/spec/client-server.md`, §7.3).
class CredentialsController extends ChangeNotifier implements CredentialPrompt {
  CredentialsController({required this.onAnswer});

  /// Куда уходит ответ: за границу, тому, кто спросил.
  final void Function(String askId, String realm, Credential? credential) onAnswer;

  String? _askId;
  CredentialRequest? _pending;

  @override
  CredentialRequest? get pending => _pending;

  /// Ядро спрашивает: показать вопрос.
  ///
  /// Второй вопрос поверх первого приложение задать не может — окно модальное,
  /// — а ядро второго и не задаёт: об одной области оно спрашивает один раз.
  void show(String askId, CredentialRequest request) {
    _askId = askId;
    _pending = request;
    notifyListeners();
  }

  /// Ответ пользователя; null — отказался.
  @override
  void answer(Credential? credential) {
    final askId = _askId;
    final request = _pending;
    if (askId == null || request == null) {
      return;
    }

    _askId = null;
    _pending = null;
    onAnswer(askId, request.realm, credential);
    notifyListeners();
  }

  @override
  void dispose() {
    // Незаконченный вопрос закрывается отказом: иначе тот, кто ждёт ответа по
    // ту сторону, остался бы висеть навсегда.
    if (_askId case final askId?) {
      onAnswer(askId, _pending?.realm ?? '', null);
    }
    _askId = null;
    _pending = null;
    super.dispose();
  }
}
