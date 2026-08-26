import 'package:fc_api/fc_api.dart';

import 'shell_command.dart';
import 'terminal_session.dart';
import 'terminal_settings.dart';

/// Постоянная сессия оболочки — одна на приложение.
///
/// Служба, а не поле экрана: экран открывают и закрывают, а оболочка живёт всё
/// время работы приложения. Заводится **лениво**, при первом `Ctrl-O`:
/// приложение, в котором терминал ни разу не открывали, лишнего процесса не
/// держит.
class ShellSession {
  ShellSession({required this.launcher, required this.settings});

  final PtyLauncher launcher;
  final TerminalSettings Function() settings;

  TerminalSession? _session;

  /// Оболочку уже запускали.
  bool get started => _session != null;

  /// Сессия; заводит её, если ещё не заводили.
  ///
  /// [directory] — откуда оболочка начнёт, и учитывается он только при первом
  /// запуске: дальше её каталог принадлежит ей самой (`spec/terminal.md`, §6).
  TerminalSession sessionIn(String? directory) {
    final current = _session;
    if (current != null) {
      return current;
    }

    final options = settings();
    final shell = ShellCommand.interactive(options.shell.isEmpty ? ShellCommand.defaultShell() : options.shell);
    return _session = TerminalSession.start(
      launcher,
      executable: shell.executable,
      arguments: shell.arguments,
      workingDirectory: directory,
      maxLines: options.maxLines,
    );
  }

  /// Приложение уходит — уходит и оболочка.
  void close() {
    _session?.dispose();
    _session = null;
  }
}
