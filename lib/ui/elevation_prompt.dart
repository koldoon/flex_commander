import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Окно предложения сделать что-то от администратора — экранная половина.
///
/// Само действие идёт по ту сторону границы: ему нужны и оболочка, и
/// псевдотерминал. Здесь только показ и ответ
/// (`docs/spec/client-server.md`, §7.3).
class ElevationPrompt extends ChangeNotifier implements Elevation {
  ElevationPrompt({required this.onAnswer, required bool Function() allowed}) : _allowed = allowed;

  /// Куда уходит ответ: за границу, тому, кто предложил.
  final void Function(String askId, bool agreed) onAnswer;

  final bool Function() _allowed;

  String? _askId;
  ElevationRequest? _pending;

  @override
  bool get enabled => _allowed();

  @override
  ElevationRequest? get pending => _pending;

  /// Ядро предлагает: показать вопрос.
  void show(String askId, ElevationRequest request) {
    _askId = askId;
    _pending = request;
    notifyListeners();
  }

  @override
  void answer(bool agreed) {
    final askId = _askId;
    if (askId == null) {
      return;
    }
    _askId = null;
    _pending = null;
    onAnswer(askId, agreed);
    notifyListeners();
  }

  @override
  void dispose() {
    // Незаконченный вопрос закрывается отказом: тот, кто ждёт по ту сторону,
    // иначе остался бы висеть навсегда.
    if (_askId case final askId?) {
      onAnswer(askId, false);
    }
    _askId = null;
    _pending = null;
    super.dispose();
  }
}
