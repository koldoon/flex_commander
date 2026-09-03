import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Чем и как запускается оболочка **на этой машине**.
///
/// Единственное место, знающее про устройство оболочек, — и единственное, что
/// придётся трогать, когда дойдут руки до Windows. Живёт здесь, а не в модуле
/// терминала, по той же причине, по какой здесь живут буфер обмена и запуск
/// программ: это про машину, а не про то, кто ею пользуется. На той стороне
/// `ssh` всё это решает сервер, и спорить с ним нам нечем.
class LocalShellCommand {
  const LocalShellCommand(this.executable, this.arguments);

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
  /// системный `PATH` без `/opt/homebrew/bin`, а дописывает его `~/.zprofile`
  /// — файл **login**-оболочки. Без него в терминале не нашлось бы ничего,
  /// поставленного через Homebrew.
  ///
  /// Плата — чтение `.zprofile` и `.zshrc` на каждый запуск: доли секунды,
  /// зависящие от того, что человек туда сложил.
  factory LocalShellCommand.line(String shell, String command) {
    if (_isWindowsShell(shell)) {
      return LocalShellCommand(shell, ['/c', command]);
    }
    return LocalShellCommand(shell, ['-lic', command]);
  }

  /// Оболочка, живущая своей жизнью: та самая постоянная сессия.
  factory LocalShellCommand.interactive(String shell) {
    if (_isWindowsShell(shell)) {
      return LocalShellCommand(shell, const []);
    }
    return LocalShellCommand(shell, const ['-l', '-i']);
  }

  static bool _isWindowsShell(String shell) => shell.toLowerCase().endsWith('cmd.exe');

  final String executable;
  final List<String> arguments;
}

/// Оболочка этой машины — та, в которой человек и так работает.
///
/// Локальная половина [ShellHost]: провайдер локальной ФС умеет выполнять
/// команды, потому что приложение на этой машине и запущено.
class LocalShellHost implements ShellHost {
  const LocalShellHost({required this.launcher, required this.shellName});

  final PtyLauncher launcher;

  /// Чем запускать; пусто — тем, чем работает человек (`$SHELL`).
  ///
  /// Спрашивается всякий раз, а не запоминается: настройку правят в окне
  /// настроек, и следующая оболочка должна открыться уже новой.
  final String Function() shellName;

  /// Своя машина — `localhost`. Ключ, по которому постоянная оболочка этой
  /// машины отличается от серверных.
  @override
  String get shellLabel => 'localhost';

  /// На своей машине оболочка известна: настройка или `$SHELL`.
  @override
  String? get shellProgram => _shell;

  /// Путь этой машины оболочка этой же машины назовёт так же.
  @override
  String shellPath(String panelPath) => panelPath;

  String get _shell {
    final chosen = shellName();
    return chosen.isEmpty ? LocalShellCommand.defaultShell() : chosen;
  }

  @override
  Future<PtySession> run(String command, {String? directory, int columns = 80, int rows = 24}) async {
    final shell = LocalShellCommand.line(_shell, command);
    // На своей машине ждать нечего: процесс запускаем мы сами.
    return launcher.start(
      executable: shell.executable,
      arguments: shell.arguments,
      // Каталог — параметр запуска, и досылать `cd` не нужно: процесс
      // запускаем мы сами. На той стороне `ssh` так уже нельзя.
      workingDirectory: directory,
      columns: columns,
      rows: rows,
    );
  }

  @override
  Future<PtySession> shell({String? directory, int columns = 80, int rows = 24}) async {
    final shell = LocalShellCommand.interactive(_shell);
    return launcher.start(
      executable: shell.executable,
      arguments: shell.arguments,
      workingDirectory: directory,
      columns: columns,
      rows: rows,
    );
  }
}
