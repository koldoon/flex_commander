import 'package:fc_api/fc_api.dart';

import 'command_line_state.dart';
import 'command_line_view.dart';
import 'shell_session.dart';
import 'system_pty.dart';
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
  ShellTerminal({PtyLauncher? pty}) : _pty = pty;

  final PtyLauncher? _pty;

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

    // Псевдотерминал пригодится не одному терминалу — но владеет им тот, кто
    // его принёс.
    registry.service<PtyLauncher>((services) => _pty ?? const SystemPtyLauncher());
    registry.service<ShellSession>(
      (services) => _shell ??= ShellSession(launcher: services.resolve<PtyLauncher>(), settings: settingsOf),
    );

    registry.view<CommandLineState>((context, state) => CommandLineView(state: state));
    registry.view<TerminalScreen>((context, state) => TerminalScreenView(screen: state));
    registry.view<CommandRunScreen>((context, state) => CommandRunView(screen: state));

    // Полоса ставится стартовой командой, а не здесь: во время объявления нет
    // ни приложения, ни настроек.
    registry.startup((context) => InstallCommandLineCommand(settings: settingsOf, save: settings.save));

    registry.command((context) => FocusCommandLineCommand());
    registry.command((context) => LeaveCommandLineCommand());
    registry.command(
      (context) => RunCommandLineCommand(launcher: () => context.resolve<PtyLauncher>(), settings: settingsOf),
    );
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
