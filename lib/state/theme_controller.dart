import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

/// Оформление приложения — реализация [ThemeService].
///
/// Тема нужна всегда: значений оформления в API нет вовсе — он описывает роли,
/// а красит модуль. Приложение, в котором оформления не объявил никто, не
/// собирается: это ошибка сборки, а не повод рисовать чем попало.
class ThemeController extends ChangeNotifier implements ThemeService {
  ThemeController([List<FcThemeSpec> themes = const []]) {
    for (final theme in themes) {
      register(theme);
    }
  }

  final List<FcThemeSpec> _themes = [];
  String? _currentId;

  @override
  List<FcThemeSpec> get available => List.unmodifiable(_themes);

  @override
  FcThemeSpec get current {
    for (final theme in _themes) {
      if (theme.id == _currentId) {
        return theme;
      }
    }
    if (_themes.isEmpty) {
      // Красить нечем: значений оформления в API нет, их приносит модуль.
      throw StateError('Ни один модуль не объявил оформление');
    }
    // Выбранной темы нет: её модуль могли отключить между запусками.
    return _themes.first;
  }

  @override
  void register(FcThemeSpec spec) {
    final existing = _themes.indexWhere((theme) => theme.id == spec.id);
    if (existing >= 0) {
      _themes[existing] = spec;
    } else {
      _themes.add(spec);
    }
    notifyListeners();
  }

  @override
  void use(String id) {
    if (_currentId == id) {
      return;
    }
    if (!_themes.any((theme) => theme.id == id)) {
      // Незнакомое имя: в настройках могло остаться имя отключённого модуля.
      return;
    }
    _currentId = id;
    notifyListeners();
  }
}
