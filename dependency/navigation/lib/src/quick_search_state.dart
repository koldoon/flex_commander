import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Быстрый поиск: набранное и панель, по которой идут.
///
/// **Содержимое статусной области, а не поле панели.** Под панелью для такого и
/// заведено место (`leftStatus`/`rightStatus`), и стопка там выкладывается
/// столбцом: идёт работа — под ней поиск, и одно другого не прячет. Панель при
/// этом остаётся панелью: её высота, её курсор, её строка состояния про то, что
/// под курсором.
///
/// Само присутствие этого состояния и есть «режим включён»: отдельного признака
/// нет, и рассогласовать их поэтому невозможно.
class QuickSearchState extends ChangeNotifier implements ViewportState {
  QuickSearchState({required this.panel, required this.onLeave}) : _directory = panel.directory?.pathString {
    panel.addListener(_watchPanel);
  }

  final Panel panel;

  /// Как уйти: убрать себя из области. Зовётся и по `Esc`, и когда панель
  /// сменила каталог.
  final void Function() onLeave;

  String get pattern => _pattern;
  String _pattern = '';

  String? _directory;

  void setPattern(String value) {
    if (_pattern == value) {
      return;
    }
    _pattern = value;
    notifyListeners();
  }

  /// Панель ушла в другой каталог — искать больше не в чем.
  ///
  /// Образец относится к **тому** списку: в новом он ничего не значит и вводил
  /// бы в заблуждение.
  void _watchPanel() {
    final now = panel.directory?.pathString;
    if (now != _directory) {
      _directory = now;
      onLeave();
    }
  }

  /// Клавиши принадлежат поиску, пока полоса на экране.
  ///
  /// На системный фокус это не влияет: статусная область активной не бывает, а
  /// шелл фокусирует только активную. Зато по этому свойству другие узнают, что
  /// набор занят, — так командная строка в режиме `mc` уступает поиску буквы,
  /// не зная о нём ничего.
  @override
  bool get takesKeyboard => true;

  @override
  void close() {
    panel.removeListener(_watchPanel);
    dispose();
  }
}
