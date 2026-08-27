import 'dart:async';

import 'package:fc_api/fc_api.dart';

import 'command_line_state.dart';
import 'completion.dart';
import 'shell_command.dart';
import 'shell_session.dart';
import 'terminal_screens.dart';
import 'terminal_session.dart';
import 'terminal_settings.dart';

/// Строка, стоящая внизу, — или null, если модуля там нет.
CommandLineState? _lineOf(Application app) {
  final content = app.view.contentAt(ViewportPosition.bottom);
  return content is CommandLineState ? content : null;
}

/// Отдать ввод командной строке.
///
/// Клавишей, а не печатью: печатный символ в панели — это переход к имени, и
/// отнимать его нельзя (`spec/terminal.md`, §5).
class FocusCommandLineCommand extends AppCommand {
  static const String commandId = 'terminal.focusLine';

  @override
  String get id => commandId;

  @override
  String get label => 'Command line';

  @override
  String get description => 'Move the input to the command line below the panels';

  @override
  Set<String> get keywords => const {'shell', 'prompt', 'type command'};

  /// Приглушённой строке ввод не отдаётся.
  ///
  /// На `ssh://` и в архиве поля ввода нет вовсе — строка объясняет, почему, —
  /// и просить фокус там не для чего. Забери она ввод, курсора не появилось бы
  /// нигде, а клавиши панели перестали бы работать: ровно тот разъезд, ради
  /// которого видимое состояние здесь главнее.
  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app)?.enabled ?? false;

  @override
  Future<void> execute(CommandContext context) async {
    context.app.view.setFocus(ViewportPosition.bottom);
  }
}

/// Вернуть ввод панели. Набранное остаётся: вернуться — то же одно нажатие.
class LeaveCommandLineCommand extends AppCommand {
  static const String commandId = 'terminal.leaveLine';

  @override
  String get id => commandId;

  @override
  String get label => 'Back to panel';

  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final line = _lineOf(context.app);
    // Первый `Esc` отказывается от выбора и возвращает набранное руками;
    // ввод при этом остаётся в строке — человек ещё не закончил.
    if (line != null && line.isCompleting && line.cancelCompletion()) {
      return;
    }

    final panel = line?.panel;
    if (panel != null) {
      context.app.activate(panel);
    }
  }
}

/// Шаг по истории команд.
class HistoryCommand extends AppCommand {
  HistoryCommand({required this.id, required this.label, required this.back});

  static const String previousId = 'terminal.historyPrevious';
  static const String nextId = 'terminal.historyNext';

  @override
  final String id;

  @override
  final String label;

  final bool back;

  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final line = _lineOf(context.app);
    back ? line?.previous() : line?.next();
  }
}

/// Вставить в строку имя объекта под курсором или его полный путь.
class InsertNodeCommand extends AppCommand {
  InsertNodeCommand({required this.id, required this.label, required this.fullPath});

  static const String nameId = 'terminal.insertName';
  static const String pathId = 'terminal.insertPath';

  @override
  final String id;

  @override
  final String label;

  final bool fullPath;

  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app) != null && _valueOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final value = _valueOf(context.app);
    if (value != null) {
      _lineOf(context.app)?.insert(ShellCommand.quote(value));
    }
  }

  /// Объект берётся из панели-источника, а не из активной области: активна
  /// сейчас строка, а курсор стоит в панели.
  String? _valueOf(Application app) {
    final node = _lineOf(app)?.panel?.currentNode;
    if (node == null) {
      return null;
    }
    return fullPath ? node.pathString : node.name;
  }
}

/// Переключить, куда уходит печать в панели.
///
/// Экрана настроек ещё нет, а настройка нужна уже сейчас: команду видно в
/// списке команд и в справке, и этого довольно.
class ToggleTypingCommand extends AppCommand {
  ToggleTypingCommand({required this.settings, required this.save});

  static const String commandId = 'terminal.toggleTyping';

  final TerminalSettings Function() settings;
  final void Function() save;

  @override
  String get id => commandId;

  @override
  String get label => 'Typing goes to command line';

  @override
  String get description => 'Typing in a panel goes to the command line instead of jumping to a name';

  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final options = settings();
    options.typingGoesToLine = !options.typingGoesToLine;
    save();
    context.app.toasts.show('Typing goes to command line: ${options.typingGoesToLine ? 'On' : 'Off'}');
  }
}

/// Развернуть постоянную сессию во весь экран и обратно.
///
/// Одна команда на оба направления: это переключатель, и `Ctrl-O` работает
/// везде — из панелей, из строки, из самого терминала.
class ToggleTerminalCommand extends AppCommand {
  ToggleTerminalCommand(this.shell);

  static const String commandId = 'terminal.toggle';

  final ShellSession Function() shell;

  @override
  String get id => commandId;

  @override
  String get label => 'Terminal';

  @override
  String get description => 'The shell, full screen';

  /// Оболочку ищут по имени той оболочки, которой пользуются, — или просто
  /// «консоль».
  @override
  Set<String> get keywords => const {'shell', 'console', 'bash', 'zsh', 'command prompt'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    if (view.contentAt(ViewportPosition.fullscreen) is TerminalScreen) {
      view.popViewportContent(ViewportPosition.fullscreen);
      return;
    }
    // Сессия заводится здесь и только здесь: приложение, в котором терминал ни
    // разу не открывали, лишнего процесса не держит.
    view.pushViewportContent(
      ViewportPosition.fullscreen,
      TerminalScreen(shell().sessionIn(_lineOf(context.app)?.workingDirectory)),
    );
  }
}

/// Убрать экран отработавшей команды.
///
/// Пока команда работает, [isExecutable] отвечает «нет», и клавиша уходит
/// дальше — в саму программу: `Enter` в ответ на её вопрос должен доехать до
/// неё, а не закрыть экран.
class CloseRunCommand extends AppCommand {
  static const String commandId = 'terminal.closeRun';

  @override
  String get id => commandId;

  @override
  String get label => 'Panels';

  @override
  bool isExecutable(CommandContext context) {
    final content = context.app.view.contentAt(ViewportPosition.fullscreen);
    return content is CommandRunScreen && content.finished;
  }

  @override
  Future<void> execute(CommandContext context) async {
    context.app.view.popViewportContent(ViewportPosition.fullscreen);
  }
}

/// Печать уходит в строку — повадка `mc`.
///
/// Выигрывает у перехода к имени **порядком**: модуль терминала объявлен раньше
/// модуля навигации, а невыполнимая команда клавишу не забирает. Поэтому при
/// выключенной настройке буква достаётся панели, как раньше, и ни ядру, ни
/// навигации о настройке знать не нужно (`spec/mc-command-line.md`, §3).
class TypeIntoLineCommand extends AppCommand {
  static const String commandId = 'terminal.type';

  /// Имя значения, в котором приходит набранный символ.
  static const String characterParam = 'character';

  @override
  String get id => commandId;

  @override
  String get label => 'Type into command line';

  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app)?.typingGoesToLine ?? false;

  @override
  Future<void> execute(CommandContext context) async {
    final character = context.invocation.param<String>(characterParam);
    if (character != null && character.isNotEmpty) {
      _lineOf(context.app)?.append(character);
    }
  }
}

/// Пробел в строку — но только когда в ней уже что-то есть.
///
/// Пока строка пуста, человек работает с панелью, и `Space` там помечает
/// объект. Набрал — значит собирается выполнить, и пробел ему нужен.
class TypeSpaceCommand extends AppCommand {
  static const String commandId = 'terminal.typeSpace';

  @override
  String get id => commandId;

  @override
  String get label => 'Space into command line';

  @override
  bool isExecutable(CommandContext context) {
    final line = _lineOf(context.app);
    return line != null && line.typingGoesToLine && !line.isBlank;
  }

  @override
  Future<void> execute(CommandContext context) async => _lineOf(context.app)?.append(' ');
}

/// Стереть символ — вместо перехода на уровень вверх, пока строка не пуста.
class EraseInLineCommand extends AppCommand {
  static const String commandId = 'terminal.erase';

  @override
  String get id => commandId;

  @override
  String get label => 'Erase in command line';

  @override
  bool isExecutable(CommandContext context) {
    final line = _lineOf(context.app);
    return line != null && line.typingGoesToLine && !line.isBlank;
  }

  @override
  Future<void> execute(CommandContext context) async => _lineOf(context.app)?.eraseLast();
}

/// Очистить строку — вместо отмены работы и снятия пометки.
class ClearLineCommand extends AppCommand {
  static const String commandId = 'terminal.clearLine';

  @override
  String get id => commandId;

  @override
  String get label => 'Clear command line';

  @override
  bool isExecutable(CommandContext context) {
    final line = _lineOf(context.app);
    // Занятой панели `Esc` принадлежит целиком: отмена работы важнее уборки в
    // строке.
    return line != null && line.typingGoesToLine && !line.isBlank && !context.panel.busy;
  }

  @override
  Future<void> execute(CommandContext context) async => _lineOf(context.app)?.clear();
}

/// Вставить из буфера обмена.
///
/// В режиме `mc` поля ввода нет — значит и системной вставки нет; без команды
/// набирать длинный путь пришлось бы руками.
class PasteIntoLineCommand extends AppCommand {
  PasteIntoLineCommand(this.clipboard);

  static const String commandId = 'terminal.paste';

  final ClipboardService clipboard;

  @override
  String get id => commandId;

  @override
  String get label => 'Paste into command line';

  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app)?.typingGoesToLine ?? false;

  @override
  Future<void> execute(CommandContext context) async {
    final text = await clipboard.readText();
    if (text != null && text.isNotEmpty) {
      // Перевод строки — это выполнение, а не текст: вставляем первую строку.
      _lineOf(context.app)?.append(text.split('\n').first);
    }
  }
}

/// Дополнить набранный путь.
///
/// `Tab` свободен ровно потому, что ввод строке отдаётся отдельной клавишей
/// (`Cmd-T`): переключение панелей на нём остаётся, пока ввод у панели.
class CompletePathCommand extends AppCommand {
  CompletePathCommand({required this.forward});

  static const String commandId = 'terminal.complete';
  static const String backCommandId = 'terminal.completeBack';

  /// Вперёд по кругу; false — назад (`Shift-Tab`).
  final bool forward;

  @override
  String get id => forward ? commandId : backCommandId;

  @override
  String get label => forward ? 'Complete path' : 'Previous match';

  @override
  String get description => 'Completes a path by the beginning of a name';

  /// Выполнима всегда, пока строка есть — как и `Enter`.
  ///
  /// Иначе `Tab`, которому нечего дополнять, провалился бы в поле и увёл фокус
  /// обходом неизвестно куда.
  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final line = _lineOf(context.app);
    final panel = line?.panel;
    final directory = panel?.directory;
    if (line == null || panel == null || directory == null || !line.enabled) {
      return;
    }

    // Перебор продолжается, только если строку с прошлой вставки не трогали:
    // `Tab` после правки — это новый подбор, а не следующий кандидат.
    if (line.isCompleting && line.suggestions.isNotEmpty) {
      line.cycleCompletion(forward: forward);
      return;
    }

    final before = line.text.text;
    final selection = line.text.selection;
    final caret = selection.isValid ? selection.start : before.length;
    final token = CompletionToken.parse(before, caret);

    final source = CompletionSource(provider: panel.provider, directory: directory.pathString);
    final List<CompletionCandidate> candidates;
    try {
      candidates = await source.candidates(token);
    } on FsError {
      // Каталога нет или в него не пускают — дополнять нечем. Молча: пустой
      // ответ и есть ответ.
      line.clearCompletion();
      return;
    }

    // Чтение — операция, и пока она шла, человек мог набрать что угодно.
    if (line.text.text != before) {
      return;
    }
    line.complete(token, candidates);
  }
}

/// Выполнить набранное.
class RunCommandLineCommand extends AppCommand {
  RunCommandLineCommand({required this.launcher, required this.settings, this.showDelay = defaultShowDelay});

  static const String commandId = 'terminal.run';

  /// Сколько ждать, прежде чем показать экран молчащей команды.
  ///
  /// Молчаливая и быстрая (`mkdir`, `chmod`) не должна мигать чёрным вовсе, а
  /// молчаливая и долгая (`sleep`, `make -s`) не должна выглядеть как «ничего
  /// не произошло».
  static const Duration defaultShowDelay = Duration(milliseconds: 300);

  final PtyLauncher Function() launcher;
  final TerminalSettings Function() settings;
  final Duration showDelay;

  @override
  String get id => commandId;

  @override
  String get label => 'Run';

  /// Пока ввод у строки — выполнима всегда; пока у панели — только в режиме
  /// `mc` и только если есть что выполнять.
  ///
  /// Первое не «пока есть что выполнять»: `Enter` принадлежит строке целиком, и
  /// на пустой он должен **ничего не сделать**, а не провалиться дальше. Ниже по
  /// дереву стоит `TextField`, и он на `Enter` снимает с себя фокус
  /// (`TextInputAction.done`) — курсор пропадал, а ввод по-прежнему числился за
  /// строкой: клавиши панели не работали, пока не нажмёшь `Esc`.
  ///
  /// Второе — правило `mc`: пустая строка означает, что человек работает с
  /// панелью, и `Enter` там входит в каталог.
  @override
  bool isExecutable(CommandContext context) {
    final line = _lineOf(context.app);
    if (line == null) {
      return false;
    }
    if (context.app.view.activeArea == ViewportPosition.bottom) {
      return true;
    }
    return line.typingGoesToLine && !line.isBlank;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final line = _lineOf(app);
    if (line == null) {
      return;
    }

    // Идёт выбор — `Enter` его закрепляет, а не выполняет команду. Иначе
    // подставленный каталог тут же уезжал бы в оболочку, вместо того чтобы
    // пустить человека глубже по пути.
    if (line.isCompleting && line.suggestions.isNotEmpty) {
      line.acceptCompletion();
      return;
    }

    final command = line.text.text.trim();
    final directory = line.workingDirectory;
    if (command.isEmpty || directory == null) {
      return;
    }

    // `cd` ведёт панель, а не оболочку (`spec/terminal.md`, §7).
    final target = _cdTarget(command);
    if (target != null) {
      line.remember(command);
      line.clear();
      await line.panel?.openPath(_resolve(directory, target, app));
      return;
    }

    final options = settings();
    final shell = ShellCommand.line(options.shell.isEmpty ? ShellCommand.defaultShell() : options.shell, command);

    final TerminalSession session;
    try {
      session = TerminalSession.start(
        launcher(),
        executable: shell.executable,
        arguments: shell.arguments,
        workingDirectory: directory,
        maxLines: options.maxLines,
      );
    } catch (error) {
      // Псевдотерминала на этой платформе может не быть вовсе. Молчать нельзя,
      // но и окна ради этого не ставим: сообщения хватает.
      app.toasts.show('Shell did not start: $error');
      return;
    }

    line.remember(command);
    line.clear();
    final screen = CommandRunScreen(command: command, session: session);

    var shown = false;
    void show() {
      if (shown) {
        return;
      }
      shown = true;
      app.view.pushViewportContent(ViewportPosition.fullscreen, screen);
    }

    void onOutput() {
      if (session.producedOutput) {
        show();
      }
    }

    session.addListener(onOutput);
    final waiting = Timer(showDelay, () {
      if (!session.finished) {
        show();
      }
    });

    final code = await session.exited;
    waiting.cancel();
    session.removeListener(onOutput);

    // Молча и успешно — экран не показывается вовсе. Сказала хоть слово или
    // провалилась — остаётся до нажатия клавиши.
    if (session.producedOutput || code != 0) {
      show();
    } else if (!shown) {
      screen.close();
    }

    await _reloadPanels(app);
  }

  /// Строка вида `cd` или `cd <путь>` — и ничего больше.
  ///
  /// `cd x && make` сюда не попадает нарочно: строку с продолжением мы
  /// толковать не беремся, она уходит оболочке как есть.
  static String? _cdTarget(String command) {
    if (command == 'cd') {
      return '~';
    }
    if (!command.startsWith('cd ')) {
      return null;
    }
    final rest = command.substring(3).trim();
    if (rest.isEmpty) {
      return '~';
    }
    if (rest.contains('&&') || rest.contains('||') || rest.contains(';') || rest.contains('|')) {
      return null;
    }
    return _unquote(rest);
  }

  static String _unquote(String value) {
    if (value.length > 1 &&
        (value.startsWith("'") && value.endsWith("'") || value.startsWith('"') && value.endsWith('"'))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Путь для панели: относительный считается от каталога, в котором стоим.
  static String _resolve(String directory, String target, Application app) {
    if (target == '~') {
      return app.activePanel.provider.homePath;
    }
    if (target.startsWith('/') || target.contains(':')) {
      return target;
    }
    final base = directory.endsWith('/') ? directory : '$directory/';
    return '$base$target';
  }

  /// Перечитать панели: команда могла создать, удалить и переименовать что
  /// угодно, и показывать после неё прежний список нельзя.
  ///
  /// Только те, что стоят на настоящей файловой системе: перечитывать `ssh://`
  /// из-за локальной команды — лишний поход по сети.
  static Future<void> _reloadPanels(Application app) async {
    for (final position in const [ViewportPosition.left, ViewportPosition.right]) {
      final panel = app.view.panelAt(position);
      if (panel != null && panel.provider.capabilities.realFileSystem) {
        await panel.reload();
      }
    }
  }
}
