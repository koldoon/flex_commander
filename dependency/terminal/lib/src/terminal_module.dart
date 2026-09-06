import 'dart:async';

import 'package:fc_api/fc_api.dart';
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
/// Один класс на обе стороны, и делятся они здесь ровно посередине: сама
/// оболочка — процесс и соединение — живёт в ядре, а разбор её вывода, лента и
/// клавиши обратно — на экране (`docs/spec/client-server.md`, §5.1.5).
///
/// Класс называется так, а не `Terminal`: последнее занято `xterm`, и два
/// `Terminal` в одном модуле путали бы и человека, и импорт.
class ShellTerminal implements FcBackendModule, FcFrontendModule, FcModuleLifecycle {
  ShellTerminal();

  /// Постоянная сессия: держится здесь, чтобы было чем закрыть её при выходе.
  ///
  /// Поле — то немногое, чего у модуля обычно нет. Держать его можно ровно
  /// потому, что оно принадлежит **одной** стороне: экземпляров модуля два,
  /// по одному на изолят, и общего состояния у них быть не должно.
  ShellSession? _shell;

  @override
  String get id => 'fc.terminal';

  @override
  String get title => 'Terminal';

  /// От ядровой половины здесь одна вещь: чем запускать оболочку. Настройка
  /// эта пользовательская и живёт у терминала, а нужна тому, кто запускает, —
  /// то есть локальной файловой системе. Службой они и сообщаются, не зная
  /// друг о друге.
  @override
  void installBackend(BackendRegistry registry) {
    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    TerminalSettings settingsOf() => settings.section(TerminalSettings.new);

    registry.service<ShellPreference>((services) => _ChosenShell(settingsOf));
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    TerminalSettings settingsOf() => settings.section(TerminalSettings.new);

    registry.service<ShellSession>((services) => _shell ??= ShellSession(settings: settingsOf));

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'typingGoesToLine',
          defaultValue: false,
          title: strings.tr('Typing goes to the command line'),
          description: strings.tr('The mc habit: no jump-to-name by the first letter'),
          read: () => settingsOf().typingGoesToLine,
          write: (value) => settingsOf().typingGoesToLine = value,
        ),
        SettingsField.flag(
          'runExecutables',
          defaultValue: true,
          title: strings.tr('Enter runs executable files'),
          description: strings.tr('A file with the +x bit runs in the terminal instead of going to the system'),
          read: () => settingsOf().runExecutables,
          write: (value) => settingsOf().runExecutables = value,
        ),
        SettingsField.text(
          'shell',
          title: strings.tr('Shell'),
          hint: r'$SHELL',
          description: strings.tr('Empty means the shell you work in'),
          note: strings.tr('Applies to the next session (⌃O)'),
          read: () => settingsOf().shell,
          write: (value) => settingsOf().shell = value,
        ),
        SettingsField.choice(
          'afterCommand',
          title: strings.tr('When a command ends'),
          description: strings.tr('What to do with the terminal screen once the command is done'),
          options: {
            TerminalSettings.waitAfterCommand: strings.tr('Wait for a key'),
            TerminalSettings.hideAfterCommand: strings.tr('Hide it'),
          },
          defaultValue: TerminalSettings.defaultAfterCommand,
          read: () => settingsOf().afterCommand,
          write: (value) => settingsOf().afterCommand = value,
        ),
        SettingsField.integer(
          'maxLines',
          defaultValue: TerminalSettings.defaultMaxLines,
          title: strings.tr('Scrollback'),
          unit: strings.tr('lines'),
          min: 100,
          max: 200000,
          note: strings.tr('Applies to the next session (⌃O)'),
          read: () => settingsOf().maxLines,
          write: (value) => settingsOf().maxLines = value,
        ),
      ], save: settings.save);
    });

    registry.view<CommandLineState>((context, state) => CommandLineView(state: state));
    registry.view<TerminalScreen>((context, state) => TerminalScreenView(screen: state));
    registry.view<CommandRunScreen>((context, state) => CommandRunView(screen: state));

    // Полоса ставится стартовой командой, а не здесь: во время объявления нет
    // ни приложения, ни настроек.
    registry.startup((context) => InstallCommandLineCommand(settings: settingsOf, save: settings.save));
    registry.startup((context) => _FollowShellCommand(() => context.resolve<ShellSession>()));
    registry.startup((context) => _WarmShellCommand(shells: () => context.resolve<ShellSession>()));

    registry.command((context) => FocusCommandLineCommand());
    registry.command((context) => LeaveCommandLineCommand());
    registry.command(
      (context) => RunCommandLineCommand(settings: settingsOf, shells: () => context.resolve<ShellSession>()),
    );
    registry.command((context) => RunNodeCommand(settings: settingsOf, shells: () => context.resolve<ShellSession>()));
    // Подпись — ключ перевода: команда не знает, кто её показывает, а её
    // строку объявляет модуль (`docs/spec/localization.md`, §6).
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

/// Выбранная оболочка — настройкой терминала, а спрашивают её снаружи.
class _ChosenShell implements ShellPreference {
  const _ChosenShell(this._settings);

  final TerminalSettings Function() _settings;

  @override
  String get shell => _settings().shell;
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
  String get label => tr('Install command line');

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
  String get label => tr('Follow the shell');

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
/// **Только своя машина** — оболочка просится без панели вовсе. Панели к
/// этому времени ещё не открыты — стартовые команды идут раньше, — да и сервер
/// за прогрев платил бы походом по сети и, случается, вопросом о пароле;
/// спрашивать его у того, кто терминала не просил, нельзя.
///
/// Не удалось — молчим. Псевдотерминала на этой платформе может не быть вовсе,
/// но узнать об этом человек должен тогда, когда попросит терминал, а не при
/// запуске приложения.
class _WarmShellCommand extends AppCommand {
  _WarmShellCommand({required this.shells});

  final ShellSession Function() shells;

  @override
  String get id => 'terminal.warm';

  @override
  String get label => tr('Start the shell');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    // Не ждём: запуск оболочки — не часть запуска приложения, и держать первый
    // кадр ради неё незачем.
    unawaited(_warm(context.app));
  }

  Future<void> _warm(Application app) async {
    try {
      await shells().sessionIn(app);
    } on Object {
      // Молчим: терминала никто не просил. Псевдотерминала на этой платформе
      // может не быть вовсе, и узнать об этом человек должен тогда, когда
      // попросит терминал, а не при запуске приложения.
    }
  }
}

/// Русские строки терминала и командной строки.
const Map<String, String> _russian = {
  'Terminal': 'Терминал',
  'Previous command': 'Предыдущая команда',
  'Next command': 'Следующая команда',
  'Insert name': 'Вставить имя',
  'Insert path': 'Вставить путь',

  // Команды.
  'Run': 'Запустить',
  'Run in terminal': 'Запустить в терминале',
  'Run the executable under the cursor in the internal terminal': 'Запустить файл под курсором во внутреннем терминале',
  'Start the shell': 'Открыть оболочку',
  'The shell, full screen': 'Оболочка на весь экран',
  'Follow the shell': 'Идти за оболочкой',
  'Panels': 'Панели',
  'Back to panel': 'Вернуться к панелям',
  'Command line': 'Командная строка',
  'Install command line': 'Показать командную строку',
  'Move the input to the command line below the panels': 'Перевести ввод в командную строку под панелями',
  'Type into command line': 'Буква в командную строку',
  'Space into command line': 'Пробел в командную строку',
  'Paste into command line': 'Вставить в командную строку',
  'Erase in command line': 'Стереть в командной строке',
  'Clear command line': 'Очистить командную строку',
  'Complete path': 'Дополнить путь',
  'Previous match': 'Предыдущее совпадение',
  'Completes a path by the beginning of a name': 'Дополняет путь по началу имени',
  'Typing goes to command line': 'Печать — в командную строку',
  'Typing in a panel goes to the command line instead of jumping to a name':
      'Печать в панели уходит в командную строку, а не ведёт курсор к имени',
  'Typing goes to command line: On': 'Печать в командную строку: включена',
  'Typing goes to command line: Off': 'Печать в командную строку: выключена',

  // Сообщения.
  'No shell here': 'Здесь нет оболочки',
  'Shell did not start: {error}': 'Оболочка не запустилась: {error}',
  'The shell is busy': 'Оболочка занята',
  'Shell does not work here': 'Оболочка здесь не работает',
  'Tab next · Enter accept · Esc cancel': 'Tab — дальше · Enter — принять · Esc — отмена',
  '⌃O panels': '⌃O — панели',
  'running — ⌃C to interrupt': 'идёт — ⌃C прерывает',
  'done — press any key': 'готово — нажмите любую клавишу',
  'exit {code} — press any key': 'код {code} — нажмите любую клавишу',

  // Настройки.
  'Typing goes to the command line': 'Печать уходит в командную строку',
  'The mc habit: no jump-to-name by the first letter': 'Привычка mc: переход к имени по первой букве не работает',
  'Enter runs executable files': 'Enter запускает исполняемые файлы',
  'A file with the +x bit runs in the terminal instead of going to the system':
      'Файл с битом +x запускается в терминале, а не уходит системе',
  'Shell': 'Оболочка',
  'Empty means the shell you work in': 'Пусто — та оболочка, в которой вы работаете',
  'Applies to the next session (⌃O)': 'Подействует со следующего сеанса (⌃O)',
  'When a command ends': 'Когда команда закончилась',
  'What to do with the terminal screen once the command is done':
      'Что делать с экраном терминала, когда команда отработала',
  'Wait for a key': 'Ждать клавишу',
  'Hide it': 'Убрать его',
  'Scrollback': 'Память экрана',
  'lines': 'строк',
};
