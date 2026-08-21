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

  /// Верхний экран, если он умеет сообщать о себе.
  Listenable? _watched;

  /// Экраны снизу вверх — для тестов и отладки.
  List<Screen> get stack => List.unmodifiable(_stack);

  @override
  Screen? get active => _stack.isEmpty ? null : _stack.last;

  @override
  void open(Screen screen) {
    // Тот же экран второй раз — это замена, а не второй слой: два просмотрщика
    // друг над другом не стопка, а недосмотр. Заменённый закрывается: он держал
    // и своё состояние, и, может быть, аренду источника.
    _removeWhere((existing) => existing.id == screen.id);
    _stack.add(screen);
    _watchActive();
    notifyListeners();
  }

  @override
  void close(String id) {
    final before = _stack.length;
    _removeWhere((screen) => screen.id == id);
    if (_stack.length != before) {
      _watchActive();
      notifyListeners();
    }
  }

  /// Убирает экраны из стопки, давая каждому закрыться.
  ///
  /// Раньше их просто выбрасывали, и `dispose` у редактора не звался никогда:
  /// вместе с ним оставались висеть и поле ввода, и аренда архива, из которого
  /// правили файл.
  void _removeWhere(bool Function(Screen screen) matches) {
    final leaving = _stack.where(matches).toList();
    _stack.removeWhere(matches);
    for (final screen in leaving) {
      screen.close();
    }
  }

  /// Стопка говорит и о том, что происходит **внутри** верхнего экрана.
  ///
  /// Иначе ряд функциональных кнопок замирает: он подписан на стопку, а
  /// доступность его команд зависит от состояния экрана — есть ли в редакторе
  /// несохранённое, выделено ли что-нибудь в просмотрщике. Живая проверка это
  /// и показала: правку сделали, а `F2` осталась приглушённой до первого
  /// постороннего перерисовывания.
  ///
  /// Подписываться на экран самому ряду нельзя: он о том, какие бывают экраны,
  /// не знает и знать не должен.
  void _watchActive() {
    final Screen? screen = active;
    final Listenable? listenable = screen is Listenable ? screen! as Listenable : null;
    if (identical(listenable, _watched)) {
      return;
    }
    _watched?.removeListener(notifyListeners);
    _watched = listenable;
    _watched?.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _watched?.removeListener(notifyListeners);
    _watched = null;
    // Приложение уходит — уходят и экраны: открытый редактор держит аренду.
    _removeWhere((screen) => true);
    super.dispose();
  }
}
