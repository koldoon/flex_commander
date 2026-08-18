import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Оформление приложения — реализация [ThemeService].
///
/// Пока ни одна тема не установлена, приложение работает на встроенных
/// умолчаниях API ([FcThemeSpec.fallback]): модуль темы может быть отключён,
/// и это не повод не запускаться.
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
    // Выбранной темы нет: её модуль могли отключить между запусками.
    return _themes.isNotEmpty ? _themes.first : FcThemeSpec.fallback;
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
