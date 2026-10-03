import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Окно вопроса о секрете — экранная половина [Credentials].
///
/// Спрашивает обычно ядро: секрет нужен тому, кто работает с источником. Но
/// бывает, что с источником работает сам экран — просмотрщик PDF держит
/// документ на этой стороне, — и тогда спрашивает он, тем же окном
/// (`docs/spec/pdf-viewer.md`, §15). Поэтому контроллер — ещё и [Credentials]
/// для модулей экрана.
///
/// Ни одного запомненного пароля здесь нет: помнит тот, кто спрашивает, — ядро
/// своё, модуль экрана своё (`docs/spec/client-server.md`, §7.3).
class CredentialsController extends ChangeNotifier implements CredentialPrompt, Credentials {
  CredentialsController({required this.onAnswer});

  /// Куда уходит ответ на вопрос ядра: за границу, тому, кто спросил.
  final void Function(String askId, String realm, Credential? credential) onAnswer;

  /// Вопросы по очереди: окно модальное, и второй поверх первого не
  /// показывается — ждёт, пока ответят на первый.
  final List<_Ask> _queue = [];

  @override
  CredentialRequest? get pending => _queue.isEmpty ? null : _queue.first.request;

  /// Ядро спрашивает: показать вопрос.
  void show(String askId, CredentialRequest request) {
    _queue.add(_Ask(request, askId: askId));
    notifyListeners();
  }

  /// Спрашивает модуль экрана: ответ остаётся здесь и за границу не уходит.
  ///
  /// Запомненного на этой стороне нет — значит, спрашивается всегда; помнить
  /// названное — дело того, кто спрашивает.
  @override
  Future<Credential?> obtain(CredentialRequest request) {
    final ask = _Ask(request, local: Completer<Credential?>());
    _queue.add(ask);
    notifyListeners();
    return ask.local!.future;
  }

  /// Забывать нечего: здесь ничего не помнят.
  @override
  void forget(String realm) {}

  /// Ответ пользователя на [pending]; null — отказался.
  @override
  void answer(Credential? credential) {
    if (_queue.isEmpty) {
      return;
    }
    final ask = _queue.removeAt(0);
    ask.reply(credential, onAnswer);
    notifyListeners();
  }

  @override
  void dispose() {
    // Незаконченные вопросы закрываются отказом: иначе тот, кто ждёт ответа, —
    // по ту сторону границы или по эту, — остался бы висеть навсегда.
    for (final ask in _queue) {
      ask.reply(null, onAnswer);
    }
    _queue.clear();
    super.dispose();
  }
}

/// Один вопрос в очереди: ядра — с номером, свой — с ожиданием ответа.
class _Ask {
  _Ask(this.request, {this.askId, this.local});

  final CredentialRequest request;
  final String? askId;
  final Completer<Credential?>? local;

  void reply(Credential? credential, void Function(String askId, String realm, Credential? credential) onAnswer) {
    if (local case final local? when !local.isCompleted) {
      local.complete(credential);
    } else if (askId case final askId?) {
      onAnswer(askId, request.realm, credential);
    }
  }
}
