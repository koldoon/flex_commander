import 'dart:async';

import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'command_line_state.dart';
import 'command_line_view.dart';
import 'shell_session.dart';
import 'terminal_commands.dart';
import 'terminal_screens.dart';
import 'terminal_settings.dart';
import 'terminal_views.dart';

/// Оболочка в том же окне.
///
/// Две вещи, а не одна: командная строка под панелями — выполнить одну команду
/// вот здесь — и полноэкранная сессия под `Ctrl-O` — поработать в оболочке.
/// Почему их две и чем за это плачено, написано в `docs/spec/terminal.md`, §8.
///
/// Класс называется так, а не `Terminal`: последнее занято `xterm`, и два
/// `Terminal` в одном модуле путали бы и человека, и импорт.
class ShellTerminal implements FcModule, FcModuleLifecycle {
  /// [pty] подставляют тесты. Умолчание — настоящий псевдотерминал: службу
  /// приносит модуль, потому что нужна она только ему.
  ShellTerminal();

  /// Постоянная сессия: держится здесь, чтобы было чем закрыть её при выходе.
  ShellSession? _shell;

  @override
  String get id => 'fc.terminal';

  @override
  String get title => 'Terminal';

  @override
  void install(FcRegistry registry) {
    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    TerminalSettings settingsOf() => settings.section(TerminalSettings.new);

    // Чем запускать оболочку **здесь** — вещь пользовательская, и живёт она в
    // настройках терминала. А нужна тому, кто запускает, то есть локальной
    // файловой системе: службой они и сообщаются, не зная друг о друге.
    registry.service<ShellPreference>((services) => _ChosenShell(settingsOf));
    registry.service<ShellSession>((services) => _shell ??= ShellSession(settings: settingsOf));

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.flag(
          'typingGoesToLine',
          defaultValue: false,
          title: 'Typing goes to the command line',
          description: 'The mc habit: no jump-to-name by the first letter',
          read: () => settingsOf().typingGoesToLine,
          write: (value) => settingsOf().typingGoesToLine = value,
        ),
        SettingsField.flag(
          'runExecutables',
          defaultValue: true,
          title: 'Enter runs executable files',
          description: 'A file with the +x bit runs in the terminal instead of going to the system',
          read: () => settingsOf().runExecutables,
          write: (value) => settingsOf().runExecutables = value,
        ),
        SettingsField.text(
          'shell',
          title: 'Shell',
          hint: r'$SHELL',
          description: 'Empty means the shell you work in',
          note: 'Applies to the next session (⌃O)',
          read: () => settingsOf().shell,
          write: (value) => settingsOf().shell = value,
        ),
        SettingsField.choice(
          'afterCommand',
          title: 'When a command ends',
          description: 'What to do with the terminal screen once the command is done',
          options: const {
            TerminalSettings.waitAfterCommand: 'Wait for a key',
            TerminalSettings.hideAfterCommand: 'Hide it',
          },
          defaultValue: TerminalSettings.defaultAfterCommand,
          read: () => settingsOf().afterCommand,
          write: (value) => settingsOf().afterCommand = value,
        ),
        SettingsField.integer(
          'maxLines',
          defaultValue: TerminalSettings.defaultMaxLines,
          title: 'Scrollback',
          unit: 'lines',
          min: 100,
          max: 200000,
          note: 'Applies to the next session (⌃O)',
          read: () => settingsOf().maxLines,
          write: (value) => settingsOf().maxLines = value,
        ),
      ], save: settings.save),
    );

    registry.view<CommandLineState>((context, state) => CommandLineView(state: state));
    registry.view<TerminalScreen>((context, state) => TerminalScreenView(screen: state));
    registry.view<CommandRunScreen>((context, state) => CommandRunView(screen: state));

    // Полоса ставится стартовой командой, а не здесь: во время объявления нет
    // ни приложения, ни настроек.
    registry.startup((context) => InstallCommandLineCommand(settings: settingsOf, save: settings.save));
    registry.startup((context) => _FollowShellCommand(() => context.resolve<ShellSession>()));
    registry.startup(
      (context) => _WarmShellCommand(
        shells: () => context.resolve<ShellSession>(),
        // Необязательно: без модуля локальной ФС греть нечего, и это не ошибка.
        host: () => context.resolveAll<ShellHost>().firstOrNull,
      ),
    );

    registry.command((context) => FocusCommandLineCommand());
    registry.command((context) => LeaveCommandLineCommand());
    registry.command(
      (context) => RunCommandLineCommand(settings: settingsOf, shells: () => context.resolve<ShellSession>()),
    );
    registry.command((context) => RunNodeCommand(settings: settingsOf, shells: () => context.resolve<ShellSession>()));
    registry.command((context) => HistoryCommand(id: HistoryCommand.previousId, label: 'Previous command', back: true));
    registry.command((context) => HistoryCommand(id: HistoryCommand.nextId, label: 'Next command', back: false));
    registry.command(
      (context) => InsertNodeCommand(id: InsertNodeCommand.nameId, label: 'Insert name', fullPath: false),
    );
    registry.command(
      (context) => InsertNodeCommand(id: InsertNodeCommand.pathId, label: 'Insert path', fullPath: true),
    );
    // Режим `mc`: печать уходит в строку. Выигрывает у перехода к имени
    // порядком объявления модулей, а не проверкой настройки в чужом модуле.
    registry.command((context) => TypeIntoLineCommand());
    registry.command((context) => TypeSpaceCommand());
    registry.command((context) => EraseInLineCommand());
    registry.command((context) => ClearLineCommand());
    registry.command((context) => PasteIntoLineCommand(context.resolve<ClipboardService>()));
    registry.command((context) => ToggleTypingCommand(settings: settingsOf, save: settings.save));

    registry.command((context) => CompletePathCommand(forward: true));
    registry.command((context) => CompletePathCommand(forward: false));
    registry.command((context) => ToggleTerminalCommand(() => context.resolve<ShellSession>()));
    registry.command((context) => CloseRunCommand());

    // Ввод строке отдаёт клавиша, а не печать: печатный символ в панели — это
    // переход к имени, и отнимать его нельзя.
    registry.binding(KeyBinding('Cmd-T', FocusCommandLineCommand.commandId));
    registry.binding(KeyBinding.inState<CommandLineState>('Esc', LeaveCommandLineCommand.commandId));
    registry.binding(KeyBinding.inState<CommandLineState>('Enter', RunCommandLineCommand.commandId));
    registry.binding(KeyBinding.inState<CommandLineState>('Cmd-Up', HistoryCommand.previousId));
    registry.binding(KeyBinding.inState<CommandLineState>('Cmd-Down', HistoryCommand.nextId));
    registry.binding(KeyBinding.inState<CommandLineState>('Cmd-Enter', InsertNodeCommand.nameId));
    registry.binding(KeyBinding.inState<CommandLineState>('Cmd-Shift-Enter', InsertNodeCommand.pathId));
    // `Tab` принадлежит строке, только пока ввод у неё: у панели за ним
    // по-прежнему переключение панелей, и в будущем режиме `mc` он там и
    // останется — без единой проверки настройки.
    registry.binding(KeyBinding.inState<CommandLineState>('Tab', CompletePathCommand.commandId));
    registry.binding(KeyBinding.inState<CommandLineState>('Shift-Tab', CompletePathCommand.backCommandId));

    // Клавиши режима `mc`. Все объявлены для панелей и все невыполнимы, пока
    // настройка выключена, — тогда клавиша достаётся тому, кто объявлен
    // следом: переходу к имени, пометке, входу в каталог, уровню вверх.
    registry.binding(KeyBinding.anyCharacter(TypeIntoLineCommand.commandId));
    registry.binding(KeyBinding('Space', TypeSpaceCommand.commandId));
    registry.binding(KeyBinding('Enter', RunCommandLineCommand.commandId));
    // После строки, а не до неё: набранное выигрывает у файла под курсором —
    // человек уже начал печатать команду, и `Enter` относится к ней.
    registry.binding(KeyBinding('Enter', RunNodeCommand.commandId));
    registry.binding(KeyBinding('Bsp', EraseInLineCommand.commandId));
    registry.binding(KeyBinding('Esc', ClearLineCommand.commandId));
    registry.binding(KeyBinding('Cmd-V', PasteIntoLineCommand.commandId));

    // `Ctrl-O` — из `mc`, и действует везде: из панелей, из строки, из самого
    // терминала. Выход должен быть один и тот же отовсюду.
    registry.binding(KeyBinding.anywhere('Ctrl-O', ToggleTerminalCommand.commandId));

    // Экран отработавшей команды убирается клавишей; пока команда работает,
    // команда закрытия невыполнима, и клавиша уходит в саму программу.
    for (final key in const ['Enter', 'Esc', 'Space']) {
      registry.binding(KeyBinding.inState<CommandRunScreen>(key, CloseRunCommand.commandId));
    }
  }

  @override
  Future<void> dispose() async => _shell?.close();
}

/// Ставит командную строку в полосу под панелями — один раз, при запуске.
class InstallCommandLineCommand extends AppCommand {
  InstallCommandLineCommand({required this.settings, required this.save});

  static const String commandId = 'terminal.install';

  final TerminalSettings Function() settings;
  final void Function() save;

  @override
  String get id => commandId;

  @override
  String get label => 'Install command line';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    context.app.view.setViewportContent(
      ViewportPosition.bottom,
      CommandLineState(app: context.app, settings: settings(), save: save),
    );
  }
}

/// Панель идёт за оболочкой — один раз, при запуске.
///
/// Стартовой командой, а не из фабрики службы: приложения в тот миг ещё нет, и
/// это не придирка — так устроен модуль нарочно ([FcContext]). А связать надо
/// именно приложение с таблицей оболочек: куда ушла оболочка, знает она, а
/// какой панели за этим идти — знает оно.
class _FollowShellCommand extends AppCommand {
  _FollowShellCommand(this.shells);

  final ShellSession Function() shells;

  @override
  String get id => 'terminal.followShell';

  @override
  String get label => 'Follow the shell';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    shells().onDirectory = (label, directory) => followShell(app, label, directory);
  }
}

/// Заводит оболочку своей машины заранее — один раз, при запуске.
///
/// Первый `Ctrl-O` и первая команда иначе ждут её запуска, чтения `.zshrc`,
/// уговора о метках и `clear`. На тяжёлой настройке это заметная пауза, и вся
/// она приходится ровно на тот миг, когда человек уже нажал клавишу.
///
/// **Только своя машина**, и берётся она службой, а не у панели. Панели к
/// этому времени ещё не открыты — стартовые команды идут раньше, — да и сервер
/// за прогрев платил бы походом по сети и, случается, вопросом о пароле;
/// спрашивать его у того, кто терминала не просил, нельзя.
///
/// Не удалось — молчим. Псевдотерминала на этой платформе может не быть вовсе,
/// но узнать об этом человек должен тогда, когда попросит терминал, а не при
/// запуске приложения.
class _WarmShellCommand extends AppCommand {
  _WarmShellCommand({required this.shells, required this.host});

  final ShellSession Function() shells;
  final ShellHost? Function() host;

  @override
  String get id => 'terminal.warm';

  @override
  String get label => 'Start the shell';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final local = host();
    if (local == null) {
      return;
    }
    // Не ждём: запуск оболочки — не часть запуска приложения, и держать первый
    // кадр ради неё незачем.
    unawaited(_warm(local));
  }

  Future<void> _warm(ShellHost host) async {
    try {
      await shells().sessionIn(host, null);
    } on Object {
      // Молчим: терминала никто не просил.
    }
  }
}

/// Выбранная оболочка — настройкой терминала, а спрашивают её снаружи.
class _ChosenShell implements ShellPreference {
  const _ChosenShell(this._settings);

  final TerminalSettings Function() _settings;

  @override
  String get shell => _settings().shell;
}
