import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'terminal_session.dart';

/// Постоянная сессия во весь экран.
///
/// Показ, а не запуск: сессия живёт всё время работы приложения, а экран —
/// только пока на него смотрят. Поэтому [close] её и не трогает: `Ctrl-O`
/// вернёт ту же оболочку со всей историей вывода.
class TerminalScreen extends ChangeNotifier implements ViewportState {
  TerminalScreen(this.session);

  final TerminalSession session;

  @override
  bool get takesKeyboard => true;

  @override
  void close() {}
}

/// Команда из строки, пока на неё смотрят.
///
/// Показывает **ту же** сессию, что и `Ctrl-O`: оболочка одна, и команда ушла в
/// неё строкой. Отсюда следует главное — экран сессией **не владеет**. Раньше
/// владел: у каждого запуска был свой процесс, и вместе с экраном уходил он.
///
/// Конец команды экрану сообщают снаружи ([finish]): сессия жива и после неё,
/// и спросить у неё «ты закончилась?» больше нельзя — она и не начиналась.
class CommandRunScreen extends ChangeNotifier implements ViewportState {
  CommandRunScreen({required this.command, required this.session}) {
    session.addListener(notifyListeners);
  }

  /// Что набрали — показывается в шапке.
  final String command;

  final TerminalSession session;

  /// Команда закончилась: с этого мгновения экран можно закрыть клавишей, а до
  /// того клавиши принадлежат ей самой.
  bool get finished => _exitCode != null;

  int? get exitCode => _exitCode;
  int? _exitCode;

  /// Команда кончилась — с таким кодом.
  void finish(int code) {
    if (_exitCode != null) {
      return;
    }
    _exitCode = code;
    notifyListeners();
  }

  @override
  bool get takesKeyboard => true;

  /// Убран с глаз; оболочка при этом остаётся жить — `Ctrl-O` вернёт к ней со
  /// всей историей.
  @override
  void close() {
    if (!finished) {
      return;
    }
    session.removeListener(notifyListeners);
  }
}
