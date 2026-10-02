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

  /// Тема, которую выбрали раньше, чем она появилась; null — такой нет.
  ///
  /// Выбор восстанавливается при запуске, а свои темы человека регистрирует
  /// редактор тем — своей стартовой командой, и порядок модулей тут ничего не
  /// обещает. Без этого запомненная своя тема при каждом запуске уступала
  /// Default: её имя приходило раньше неё самой.
  String? _wanted;

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
    if (spec.id == _wanted) {
      _currentId = spec.id;
      _wanted = null;
    }
    notifyListeners();
  }

  @override
  void forget(String id) {
    final before = _themes.length;
    _themes.removeWhere((theme) => theme.id == id);
    if (_themes.length == before) {
      return;
    }
    // Убрали выбранную — выбор переходит первой известной: [current] и так
    // отдаёт её, но сказать об этом надо, иначе имя в настройках останется от
    // темы, которой больше нет.
    if (_currentId == id) {
      _currentId = _themes.isEmpty ? null : _themes.first.id;
    }
    notifyListeners();
  }

  @override
  void use(String id) {
    if (_currentId == id) {
      _wanted = null;
      return;
    }
    if (!_themes.any((theme) => theme.id == id)) {
      // Незнакомое имя — запоминается, а не выбирается: это может быть своя
      // тема, которую ещё не зарегистрировали ([_wanted]). А может быть имя
      // отключённого модуля — тогда она не появится вовсе, и на экране так и
      // останется то, что было.
      _wanted = id;
      return;
    }
    _wanted = null;
    _currentId = id;
    notifyListeners();
  }
}
