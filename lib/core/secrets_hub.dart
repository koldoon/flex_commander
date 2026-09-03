import 'dart:async';

import 'package:fc_api/fc_api.dart';

/// Вопросы, на которые ответить может только экран.
///
/// Секреты и повышение прав устроены одинаково и разрезаны по одному месту:
/// **спрашивает** тот, кто работает с источником, — ядро; **показывает** тот, у
/// кого есть экран. Вопрос уходит событием, ответ приходит просьбой, а ждущий
/// его тем временем спит (`docs/spec/client-server.md`, §7.3).
///
/// **Помнит ответы эта сторона.** Помнит тот, кто спрашивает: 7z запускает
/// программу на каждое чтение записи, и без памяти окно появлялось бы на каждый
/// файл — а с памятью на той стороне за ним ещё и ходили бы через границу.
/// Пароли при этом не пишутся никуда: они живут в этой карте и исчезают вместе
/// с процессом.
class SecretsHub implements Credentials {
  /// Куда уходят вопросы.
  ///
  /// Ставится сервером при сборке, а не приходит в конструктор: спрашивающие
  /// заводятся раньше сервера — им нужна эта служба, — а сервер знает, кому
  /// рассылать. Пока не поставлен, вопрос задавать некому, и спросивший
  /// получает отказ, а не виснет.
  void Function(CoreEvent event)? _say;

  void connect(void Function(CoreEvent event) say) => _say = say;

  /// Запомненное — по области, к которой оно подошло.
  final Map<String, Credential> _known = {};

  /// Заданные вопросы: имя разговора → тот, кто ждёт ответа.
  final Map<String, Completer<Credential?>> _credentials = {};
  final Map<String, Completer<bool>> _elevations = {};

  /// Уже идущий вопрос об этой области; второй такой задавать незачем.
  final Map<String, Completer<Credential?>> _asking = {};

  var _nextAsk = 0;

  @override
  Future<Credential?> obtain(CredentialRequest request) {
    if (_known[request.realm] case final known?) {
      return Future.value(known);
    }

    // Спросить могут двое сразу — обе панели открывают один архив, — и тогда
    // второй ждёт того же ответа, а не своей очереди.
    if (_asking[request.realm] case final waiting?) {
      return waiting.future;
    }

    final say = _say;
    if (say == null) {
      return Future.value();
    }

    final askId = 'secret#${_nextAsk++}';
    final answer = Completer<Credential?>();
    _credentials[askId] = answer;
    _asking[request.realm] = answer;
    say(CredentialAsked(askId, request));
    return answer.future;
  }

  @override
  void forget(String realm) => _known.remove(realm);

  /// Помнит ли что-то про эту область. Нужно проверкам; сам секрет наружу не
  /// отдаётся.
  bool knows(String realm) => _known.containsKey(realm);

  /// Предложить сделать что-то от администратора.
  Future<bool> askElevation(ElevationRequest request) {
    final say = _say;
    if (say == null) {
      return Future.value(false);
    }

    final askId = 'sudo#${_nextAsk++}';
    final answer = _elevations[askId] = Completer<bool>();
    say(ElevationAsked(askId, request));
    return answer.future;
  }

  /// Экран ответил про секрет; null — отказался.
  void answerCredential(String askId, Credential? credential, {required String realm}) {
    final waiting = _credentials.remove(askId);
    _asking.remove(realm);
    if (credential != null) {
      _known[realm] = credential;
    }
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete(credential);
    }
  }

  /// Экран ответил про повышение.
  void answerElevation(String askId, {required bool agreed}) {
    final waiting = _elevations.remove(askId);
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete(agreed);
    }
  }

  /// Ядро уходит: ждущих бросать нельзя — иначе работа встанет навсегда.
  void dispose() {
    for (final waiting in _credentials.values) {
      if (!waiting.isCompleted) {
        waiting.complete(null);
      }
    }
    for (final waiting in _elevations.values) {
      if (!waiting.isCompleted) {
        waiting.complete(false);
      }
    }
    _credentials.clear();
    _elevations.clear();
    _asking.clear();
    _known.clear();
  }
}
