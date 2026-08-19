import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';

/// Стопка экранов приложения.
///
/// Внизу — тот, с которого начинают (файловые панели), сверху — открытые поверх
/// него. Виден верхний; закрывается — возвращается то, что было под ним.
///
/// Стопка списком, а не одним значением: просмотрщик, открытый из панелей,
/// обязан вернуть панели ровно такими, какими они были, — а не открывать их
/// заново.
class ScreensController extends ChangeNotifier implements Screens {
  final List<Screen> _stack = [];

  /// Экраны снизу вверх — для тестов и отладки.
  List<Screen> get stack => List.unmodifiable(_stack);

  @override
  Screen? get active => _stack.isEmpty ? null : _stack.last;

  @override
  void open(Screen screen) {
    // Тот же экран второй раз — это замена, а не второй слой: два просмотрщика
    // друг над другом не стопка, а недосмотр.
    _stack.removeWhere((existing) => existing.id == screen.id);
    _stack.add(screen);
    notifyListeners();
  }

  @override
  void close(String id) {
    final before = _stack.length;
    _stack.removeWhere((screen) => screen.id == id);
    if (_stack.length != before) {
      notifyListeners();
    }
  }
}
