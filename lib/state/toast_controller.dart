import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

/// Реализация [Toasts]: одно сообщение и таймер под ним.
class ToastController extends ChangeNotifier implements Toasts {
  ToastController({this.duration = defaultDuration});

  /// Сколько сообщение висит на экране.
  ///
  /// Столько, чтобы успеть прочитать короткую строку, но не столько, чтобы
  /// мешать: сообщение появляется поверх панели, а работать в ней продолжают.
  static const Duration defaultDuration = Duration(seconds: 2);

  final Duration duration;

  Toast? _current;
  Timer? _timer;
  int _lastId = 0;

  @override
  Toast? get current => _current;

  @override
  void show(String message) {
    _timer?.cancel();
    _current = Toast(id: ++_lastId, message: message);
    // Время идёт от последнего сообщения, а не от первого: иначе третье
    // переключение подряд исчезало бы почти сразу после появления.
    _timer = Timer(duration, hide);
    notifyListeners();
  }

  @override
  void hide() {
    _timer?.cancel();
    _timer = null;
    if (_current == null) {
      return;
    }
    _current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Таймер не должен пережить приложение: в тестах оставшийся таймер роняет
    // проверку — и правильно делает.
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
