import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'command_line_state.dart';
import 'completion.dart';
import 'shell_command.dart';
import 'shell_session.dart';
import 'terminal_session.dart';
import 'terminal_run.dart';
import 'terminal_screens.dart';
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
  String get label => tr('Command line');

  @override
  String get description => tr('Move the input to the command line below the panels');

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
  String get label => tr('Back to panel');

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
  HistoryCommand({required this.id, required String label, required this.back}) : _label = label;

  static const String previousId = 'terminal.historyPrevious';
  static const String nextId = 'terminal.historyNext';

  @override
  final String id;

  /// Английская подпись — она же ключ перевода: команда одна, а имён у неё два.
  final String _label;

  @override
  String get label => tr(_label);

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
  InsertNodeCommand({required this.id, required String label, required this.fullPath}) : _label = label;

  static const String nameId = 'terminal.insertName';
  static const String pathId = 'terminal.insertPath';

  @override
  final String id;

  /// Английская подпись — она же ключ перевода.
  final String _label;

  @override
  String get label => tr(_label);

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
    final entry = _lineOf(app)?.panel?.currentEntry;
    if (entry == null) {
      return null;
    }
    return fullPath ? entry.path : entry.name;
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
  String get label => tr('Typing goes to command line');

  @override
  String get description => tr('Typing in a panel goes to the command line instead of jumping to a name');

  @override
  bool isExecutable(CommandContext context) => _lineOf(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final options = settings();
    options.typingGoesToLine = !options.typingGoesToLine;
    save();
    context.app.toasts.show(
      options.typingGoesToLine ? tr('Typing goes to command line: On') : tr('Typing goes to command line: Off'),
    );
  }
}

/// Развернуть постоянную сессию во весь экран и обратно.
///
/// Одна команда на оба направления: это переключатель, и `Ctrl-O` работает
/// везде — из панелей, из строки, из самого терминала.
/// Оболочка того места, где стоит панель; null — выполнять здесь негде.
///
/// Спрашивается у **провайдера**, а не у реестра служб: на локальной панели это
/// своя машина, на `ssh://` — сервер, а внутри архива оболочки нет вовсе.
/// Панель идёт за оболочкой, если та ушла сама.
///
/// Идёт **активная**, а не всякая на этом месте: две панели могут стоять на
/// одной и той же машине, и `cd` в оболочке не повод дёргать обе. Активная —
/// та, из которой команду и запускали: и из строки, и из развёрнутого
/// терминала.
///
/// Только на настоящей файловой системе: каталог оболочки на сервере — путь
/// **там**, и панели он ничего не говорит.
void followShell(Application app, String shellLabel, String directory) {
  final panel = app.activePanel;
  if (panel.source.shellLabel != shellLabel) {
    return;
  }
  if (!panel.source.capabilities.realFileSystem || panel.currentPath == directory) {
    return;
  }
  unawaited(panel.openPath(directory));
}

/// Забирает ли клавиши то, что стоит **под** активной панелью.
///
/// Статусная область — место для полос под панелью: ход работы, быстрый поиск.
/// Работа клавиш не берёт, поиск берёт, и различает их само содержимое
/// ([ViewportState.takesKeyboard]), а не тот, кто спрашивает.
bool statusTakesKeys(Application app) {
  final position = app.view.activeArea.status;
  if (position == null) {
    return false;
  }
  return app.view.contentAt(position)?.takesKeyboard ?? false;
}

/// Есть ли у панели где выполнять команды.
///
/// Спрашивается у снимка источника, а не у провайдера: самого источника по эту
/// сторону нет вовсе, и это не потеря — «есть ли здесь оболочка» и так вопрос
/// про место, а не про объект.
bool hasShell(Session? panel) => panel != null && panel.source.isShellHost;

/// Путь объекта так, как назовёт его **оболочка** панели.
///
/// Считается, а не спрашивается: объект лежит в каталоге панели, а её каталог
/// оболочка уже назвала — остаётся приставить имя тем же разделителем, каким
/// приставил его сам источник. Лишнего похода за границу на каждый `Enter` это
/// стоить не должно.
String shellPathOf(Session panel, FileEntry entry) =>
    entry.path.startsWith(panel.currentPath)
        ? panel.shellDirectory + entry.path.substring(panel.currentPath.length)
        : entry.path;

class ToggleTerminalCommand extends AppCommand {
  ToggleTerminalCommand(this.shell);

  static const String commandId = 'terminal.toggle';

  final ShellSession Function() shell;

  /// Работающая команда, убранная с глаз этой же клавишей.
  ///
  /// Держится здесь, потому что вернуть её больше некому: в области её уже нет,
  /// а процесс продолжает работать.
  CommandRunScreen? _hidden;

  @override
  String get id => commandId;

  @override
  String get label => tr('Terminal');

  @override
  String get description => tr('The shell, full screen');

  /// Оболочку ищут по имени той оболочки, которой пользуются, — или просто
  /// «консоль».
  @override
  Set<String> get keywords => const {'shell', 'console', 'bash', 'zsh', 'command prompt'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    final content = view.contentAt(ViewportPosition.fullscreen);

    // Над работающей командой вторая оболочка не встаёт: `Ctrl-O` — это «туда и
    // обратно», а не «ещё один терминал». Экран убирается с глаз, процесс
    // продолжает работать, и та же клавиша возвращает к нему.
    if (content is CommandRunScreen) {
      _hidden = content;
      view.popViewportContent(ViewportPosition.fullscreen);
      return;
    }
    if (content is TerminalScreen) {
      view.popViewportContent(ViewportPosition.fullscreen);
      return;
    }
    // Обратно — туда же, откуда ушли: спрятанная команда возвращается прежде,
    // чем заводится оболочка.
    final hidden = _hidden;
    if (hidden != null) {
      _hidden = null;
      view.pushViewportContent(ViewportPosition.fullscreen, hidden);
      return;
    }
    // Сессия заводится здесь и только здесь: приложение, в котором терминал ни
    // разу не открывали, лишнего процесса не держит.
    final line = _lineOf(context.app);
    if (!hasShell(line?.panel)) {
      // Внутри архива выполнять негде, и молчать об этом нельзя: клавиша
      // нажата, а ничего не произошло.
      context.app.toasts.show(tr('No shell here'));
      return;
    }

    // Экран встаёт **сразу**: панели уходят в том же кадре, в котором нажали
    // клавишу. Оболочка заводится сколько нужно — на сервере это поход по
    // сети, — и до её ответа экран пуст (`spec/terminal.md`).
    final screen = TerminalScreen();
    view.pushViewportContent(ViewportPosition.fullscreen, screen);

    final TerminalSession session;
    try {
      // Аренду места берёт ядро: пока живёт оболочка, живо и соединение —
      // уйти с сервера панель вправе хоть сразу, а `htop` там обязан дожить до
      // своего конца.
      session = await shell().sessionIn(context.app, panel: line?.panel, directory: line?.workingDirectory);
    } on Object catch (error) {
      // На сервере открытие канала — поход по сети, и не удаться оно может.
      // Молчать нельзя: клавиша нажата, а экрана нет. Пустой экран при этом
      // убирается — показывать нечего.
      _close(view, screen);
      context.app.toasts.show(tr('Shell did not start: {error}', args: {'error': error}));
      return;
    }

    // Содержимое показываем не раньше, чем оболочка убрала с глаз строку
    // уговора: она отражает всё, что ей присылают, и без этой паузы человек
    // видит на кадр чужую кухню (`spec/single-shell-session.md`, §3).
    await session.ready.timeout(ShellSession.settleTimeout, onTimeout: () {});

    // Оболочка одна на место и живёт своей жизнью: пока её не показывали, она
    // могла остаться там, где её завели. Показать её надо **там, где стоит
    // панель** — иначе она не только покажет чужой каталог, но и утащит туда
    // панель: за её приглашением идёт `followShell`
    // (`spec/single-shell-session.md`).
    final at = line?.workingDirectory;
    if (at != null && at.isNotEmpty && session.lastMark?.directory != at) {
      session.input('cd ${ShellCommand.quote(at)}\n');
    }

    screen.attach(session);
  }
}

/// Убрать экран, если он всё ещё показан: пока ждали оболочку, человек мог
/// нажать `Ctrl-O` ещё раз или уйти в другое место.
void _close(ApplicationView view, TerminalScreen screen) {
  if (identical(view.contentAt(ViewportPosition.fullscreen), screen)) {
    view.popViewportContent(ViewportPosition.fullscreen);
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
  String get label => tr('Panels');

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
  String get label => tr('Type into command line');

  /// Пока под панелью стоит что-то, забирающее клавиши, буквы принадлежат ему.
  ///
  /// Так устроен быстрый поиск: его включают явно (`Ctrl-S`), и перехватывать у
  /// него набор было бы худшим из возможного — человек набирает имя, а оно
  /// уезжает в командную строку. Спрашивается **свойство содержимого**, а не
  /// «идёт ли поиск»: терминал про модуль навигации не знает и знать не должен.
  @override
  bool isExecutable(CommandContext context) =>
      !statusTakesKeys(context.app) && (_lineOf(context.app)?.typingGoesToLine ?? false);

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
  String get label => tr('Space into command line');

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
  String get label => tr('Erase in command line');

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
  String get label => tr('Clear command line');

  @override
  bool isExecutable(CommandContext context) {
    final line = _lineOf(context.app);
    // Занятой панели `Esc` принадлежит целиком: отмена работы важнее уборки в
    // строке.
    return line != null && line.typingGoesToLine && !line.isBlank && !context.session.busy;
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
  String get label => tr('Paste into command line');

  /// Пока под панелью стоит что-то, забирающее клавиши, буквы принадлежат ему.
  ///
  /// Так устроен быстрый поиск: его включают явно (`Ctrl-S`), и перехватывать у
  /// него набор было бы худшим из возможного — человек набирает имя, а оно
  /// уезжает в командную строку. Спрашивается **свойство содержимого**, а не
  /// «идёт ли поиск»: терминал про модуль навигации не знает и знать не должен.
  @override
  bool isExecutable(CommandContext context) =>
      !statusTakesKeys(context.app) && (_lineOf(context.app)?.typingGoesToLine ?? false);

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
  String get label => forward ? tr('Complete path') : tr('Previous match');

  @override
  String get description => tr('Completes a path by the beginning of a name');

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
    if (line == null || panel == null || !line.enabled) {
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

    final source = CompletionSource(
      lookup: panel.namesIn,
      directory: panel.currentPath,
      homePath: panel.source.homePath,
    );
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
  RunCommandLineCommand({required this.settings, required this.shells, this.showDelay = TerminalRun.defaultShowDelay});

  /// Оболочки — способом их спросить: команда создаётся раньше служб.
  final ShellSession Function() shells;

  static const String commandId = 'terminal.run';

  final TerminalSettings Function() settings;
  final Duration showDelay;

  @override
  String get id => commandId;

  @override
  String get label => tr('Run');

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

    // Запуск и показ — общие с запуском файла под курсором: `TerminalRun`.
    final panel = line.panel;
    if (!hasShell(panel)) {
      return;
    }

    await TerminalRun.start(
      app: app,
      shells: shells(),
      panel: panel,
      options: settings(),
      command: command,
      workingDirectory: directory,
      showDelay: showDelay,
      // Строка помнит и очищается, только когда процесс уже пошёл: не
      // запустилось — набранное остаётся на месте.
      onStarted: () {
        line.remember(command);
        line.clear();
      },
    );
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
      return app.activePanel.source.homePath;
    }
    if (target.startsWith('/') || target.contains(':')) {
      return target;
    }
    final base = directory.endsWith('/') ? directory : '$directory/';
    return '$base$target';
  }
}

/// Запустить файл под курсором во внутреннем терминале.
///
/// Живёт здесь, а не в навигации, и ничего в ней не меняет: модуль терминала
/// объявлен раньше, а невыполнимая команда клавишу не забирает. Отсюда весь
/// порядок разбора `Enter` в панели складывается сам собой — набранная строка,
/// потом исполняемый файл, потом вход в каталог (`spec/run-executables.md`, §4).
class RunNodeCommand extends AppCommand {
  RunNodeCommand({required this.settings, required this.shells, this.showDelay = TerminalRun.defaultShowDelay});

  /// Оболочки — способом их спросить: команда создаётся раньше служб.
  final ShellSession Function() shells;

  static const String commandId = 'terminal.runNode';

  final TerminalSettings Function() settings;
  final Duration showDelay;

  @override
  String get id => commandId;

  @override
  String get label => tr('Run in terminal');

  @override
  String get description => tr('Run the executable under the cursor in the internal terminal');

  @override
  Set<String> get keywords => const {'execute', 'launch', 'exec', 'script', 'binary', 'shell'};

  @override
  bool isExecutable(CommandContext context) =>
      settings().runExecutables &&
      !context.session.busy &&
      // Запускают **из каталога панели**, а он не всегда настоящий: в списке
      // находок узлы свои, а каталога у них общего нет. Раньше это выяснялось
      // уже в `execute`, и `Enter` там молча пропадал — клавишу забирала
      // команда, которой нечего было делать.
      hasShell(context.session) &&
      _runnable(context) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    final entry = _runnable(context);
    if (entry == null || !hasShell(panel)) {
      return;
    }

    // Полный путь в кавычках, а не `./имя`: не приходится гадать, совпадает ли
    // каталог панели с каталогом файла, а имя с пробелом или кавычкой не
    // разваливается на куски. Он же виден заголовком экрана.
    //
    // Путь — тот, которым его назовёт оболочка: на сервере она про адрес
    // `ssh://` не слышала.
    final command = ShellCommand.quote(shellPathOf(panel, entry));

    await TerminalRun.start(
      app: context.app,
      shells: shells(),
      panel: panel,
      options: settings(),
      command: command,
      workingDirectory: panel.shellDirectory,
      showDelay: showDelay,
      // В историю строки — как и набранное руками: это команда, выполненная в
      // этом каталоге, и повторяют её тем же `Cmd-Up`.
      onStarted: () => _lineOf(context.app)?.remember(command),
    );
  }

  /// Файл, который можно запустить, — или null.
  ///
  /// Каталог отсеивается **отдельной строкой**, и это не перестраховка:
  /// `+x` у каталога есть почти всегда (право входить в него), а
  /// `DirectoryNode` — наследник `FileNode`, и проверка «это файл» молча
  /// пропускает каталоги. Заодно отсюда следует, что `.app` на macOS
  /// открывается как каталог, каким и является.
  static FileEntry? _runnable(CommandContext context) {
    final entry = context.entry;
    // Всё, во что **входят**, запуску не подлежит: каталог, «..» и ссылка на
    // каталог. Последняя и подвела: у каталога стоит бит `+x`, ссылка на него
    // числится исполняемой — и `Enter` над `/etc` запускал `cd / && /etc`
    // вместо того, чтобы войти (`docs/spec/terminal.md`, §8).
    if (entry == null || entry.canEnter) {
      return null;
    }
    // Запускать можно только настоящий путь: внутри архива запускать нечего, а
    // на сервере — нечем, наш терминал местный.
    if (!context.session.source.capabilities.realFileSystem) {
      return null;
    }
    // Битая ссылка исполняемой числится, но вести ей некуда.
    return entry.executable && !entry.broken ? entry : null;
  }
}
