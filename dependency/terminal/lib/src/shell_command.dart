import 'dart:io';

/// Чем и как запускается набранная строка.
///
/// Отдельно от всего остального, потому что это единственное место, где модуль
/// знает про устройство оболочек, — и единственное, что придётся трогать, когда
/// дойдут руки до Windows.
class ShellCommand {
  const ShellCommand(this.executable, this.arguments);

  /// Оболочка по умолчанию — та, в которой человек работает.
  ///
  /// `$SHELL`, а не `/bin/sh`: псевдонимы, функции и настройки живут в его
  /// оболочке, и запускать команду в чужой значило бы отвечать «команда не
  /// найдена» на то, что в терминале работает.
  static String defaultShell() {
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? 'cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/sh';
  }

  /// Одна команда: выполнить и выйти.
  ///
  /// `-i` — ради псевдонимов: `ll` и `gs` человек набирает в строке ровно так
  /// же, как в терминале, и «команда не найдена» на них было бы враньём.
  ///
  /// `-l` — ради `PATH`. Приложение, запущенное из Finder, наследует куцый
  /// системный `PATH` без `/opt/homebrew/bin` (это уже описано в
  /// `providers.md`, 10), а дописывает его `~/.zprofile` — файл **login**-оболочки.
  /// Без него в терминале не нашлось бы ничего, поставленного через Homebrew.
  ///
  /// Плата — чтение `.zprofile` и `.zshrc` на каждый запуск: доли секунды,
  /// зависящие от того, что человек туда сложил.
  factory ShellCommand.line(String shell, String command) {
    if (_isWindowsShell(shell)) {
      return ShellCommand(shell, ['/c', command]);
    }
    return ShellCommand(shell, ['-lic', command]);
  }

  /// Оболочка, живущая своей жизнью: та самая постоянная сессия.
  factory ShellCommand.interactive(String shell) {
    if (_isWindowsShell(shell)) {
      return ShellCommand(shell, const []);
    }
    return ShellCommand(shell, const ['-l', '-i']);
  }

  static bool _isWindowsShell(String shell) => shell.toLowerCase().endsWith('cmd.exe');

  final String executable;
  final List<String> arguments;

  /// Строка для оболочки: пробелы и всё, что оболочка толкует, в кавычках.
  ///
  /// Нужно вставке имени и пути: файл `my report (2).txt` без кавычек
  /// превратился бы в три аргумента и скобки в придачу.
  static String quote(String value) {
    if (value.isNotEmpty && _safe.hasMatch(value)) {
      return value;
    }
    // Одинарные кавычки не толкуются вовсе — кроме самих себя, и закрыть их
    // ради одной кавычки приходится по всем правилам: `'\''`.
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static final RegExp _safe = RegExp(r'^[A-Za-z0-9._/@%+:,=-]+$');
}
