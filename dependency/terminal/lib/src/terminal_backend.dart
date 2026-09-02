import 'package:fc_core_api/fc_core_api.dart';

import 'terminal_settings.dart';

/// Оболочка в том же окне — ядровая половина.
///
/// От целого модуля здесь одна вещь: чем запускать оболочку. Настройка эта
/// пользовательская и живёт у терминала, а нужна тому, кто запускает, — то есть
/// локальной файловой системе. Службой они и сообщаются, не зная друг о друге.
class ShellTerminalBackend implements FcBackendModule {
  const ShellTerminalBackend();

  @override
  String get id => 'fc.terminal';

  @override
  String get title => 'Terminal';

  @override
  void installBackend(BackendRegistry registry) {
    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    TerminalSettings settingsOf() => settings.section(TerminalSettings.new);

    registry.service<ShellPreference>((services) => _ChosenShell(settingsOf));
  }
}

/// Выбранная оболочка — настройкой терминала, а спрашивают её снаружи.
class _ChosenShell implements ShellPreference {
  const _ChosenShell(this._settings);

  final TerminalSettings Function() _settings;

  @override
  String get shell => _settings().shell;
}
