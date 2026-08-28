import 'package:fc_api/fc_api.dart';
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

/// Работающая (или уже отработавшая) команда из строки.
///
/// В отличие от постоянной сессии — своя на каждый запуск, и вместе с экраном
/// уходит процесс: убрать её с глаз, оставив работать, в первой версии нельзя.
class CommandRunScreen extends ChangeNotifier implements ViewportState {
  CommandRunScreen({required this.command, required this.session}) {
    session.addListener(notifyListeners);
  }

  /// Что набрали — показывается в шапке.
  final String command;

  final TerminalSession session;

  /// Команда закончилась: с этого мгновения экран можно закрыть клавишей, а до
  /// того клавиши принадлежат ей самой.
  bool get finished => session.finished;

  int? get exitCode => session.exitCode;

  @override
  bool get takesKeyboard => true;

  /// Убрана с глаз, но работает: `Ctrl-O` вернёт к ней.
  ///
  /// Различать это важно: `close` у области означает «состояние убрали», а
  /// убрать с глаз работающую команду и прекратить её — не одно и то же.
  @override
  void close() {
    if (!finished) {
      return;
    }
    session.removeListener(notifyListeners);
    session.dispose();
  }
}
