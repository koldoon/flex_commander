import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Курсор на строку вверх.
class MoveCursorUpCommand extends AppCommand {
  static const String commandId = 'panel.cursor.up';

  @override
  String get id => commandId;

  @override
  String get label => tr('Cursor up');

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.moveCursor(-1);
}

/// Курсор на строку вниз.
class MoveCursorDownCommand extends AppCommand {
  static const String commandId = 'panel.cursor.down';

  @override
  String get id => commandId;

  @override
  String get label => tr('Cursor down');

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.moveCursor(1);
}

/// Курсор на первый объект, чьё имя начинается с заданного символа.
///
/// Символ приходит параметром, а не из события клавиатуры: команде всё равно,
/// набрали его на клавиатуре, выбрали в списке команд или подставил сценарий.
class GoToNameCommand extends AppCommand {
  /// Символ, с которого начинается имя.
  static const String characterParam = 'character';

  static const String commandId = 'panel.goToName';

  @override
  String get id => commandId;

  @override
  String get label => tr('Go to name');

  @override
  String get description => tr('Jump to the first item starting with the typed letter');

  /// Ищут её как поиск по панели — этим она и является.
  @override
  Set<String> get keywords => const {'search', 'filter', 'jump', 'quick search', 'find file'};

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async {
    final character = context.invocation.param<String>(characterParam)?.toLowerCase() ?? '';
    if (character.isEmpty) {
      return;
    }

    final panel = context.panel;
    final entries = panel.entries;

    // Поиск идёт от курсора вниз и по кругу: повторное нажатие той же буквы
    // переходит к следующему такому имени, а не топчется на первом.
    for (var offset = 1; offset <= entries.length; offset++) {
      final index = (panel.cursorIndex + offset) % entries.length;
      final entry = entries[index];
      // «..» — это не имя файла.
      if (entry.isParent) {
        continue;
      }
      if (entry.name.toLowerCase().startsWith(character)) {
        panel.setCursorIndex(index);
        return;
      }
    }
  }
}

/// Курсор на страницу вверх — по числу видимых строк.
class PageUpCommand extends AppCommand {
  static const String commandId = 'panel.cursor.pageUp';

  @override
  String get id => commandId;

  @override
  String get label => tr('Page up');

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.moveCursorPage(-1);
}

/// Курсор на страницу вниз.
class PageDownCommand extends AppCommand {
  static const String commandId = 'panel.cursor.pageDown';

  @override
  String get id => commandId;

  @override
  String get label => tr('Page down');

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.moveCursorPage(1);
}

/// Курсор на первый объект списка.
///
/// Стрелка влево занята именно этим — панели переключаются только Tab
/// (решение референса: `GoToFirstNodeCommand`).
class GoToFirstNodeCommand extends AppCommand {
  static const String commandId = 'panel.cursor.first';

  @override
  String get id => commandId;

  @override
  String get label => tr('First item');

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.setCursorToFirst();
}

/// Курсор на последний объект списка.
class GoToLastNodeCommand extends AppCommand {
  static const String commandId = 'panel.cursor.last';

  @override
  String get id => commandId;

  @override
  String get label => tr('Last item');

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.setCursorToLast();
}

/// Переключение активной панели.
class TogglePanelCommand extends AppCommand {
  static const String commandId = 'app.togglePanel';

  @override
  String get id => commandId;

  @override
  String get label => tr('Switch panel');

  @override
  String get description => tr('Make the other panel active');

  @override
  Set<String> get keywords => const {'other panel', 'toggle panel', 'focus'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async => context.app.toggleActivePanel();
}

/// Показать в соседней панели то, на чём стоит курсор.
///
/// Привычка `mc`: `Alt-O` — быстрый способ развести две панели по нужным
/// каталогам, не набирая путь. Курсор на каталоге — соседняя открывает **его**;
/// на файле или на «..» — каталог этой панели: файл в панели не открыть, а
/// показать рядом то, что рядом с ним, — ровно то, чего от команды и ждут.
///
/// Активной остаётся своя панель: команда показывает, а не переводит взгляд.
/// Хотели бы перевести — для этого есть `Tab`.
class OpenInOtherPanelCommand extends AppCommand {
  static const String commandId = 'panel.openInOther';

  @override
  String get id => commandId;

  @override
  String get label => tr('Open in the other panel');

  @override
  String get description => tr('Show the directory under the cursor in the panel opposite');

  @override
  Set<String> get keywords => const {'sync panels', 'cd', 'same directory'};

  /// Некуда показывать — нечего и делать: напротив бывает наложение (быстрый
  /// просмотр, находки во весь экран), и панели там сейчас нет.
  @override
  bool isExecutable(CommandContext context) => context.target != null && _pathFor(context) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final path = _pathFor(context);
    final target = context.target;
    if (path == null || target == null) {
      return;
    }
    await target.openPath(path);
  }

  /// Что показать соседке: каталог под курсором, а иначе — свой каталог.
  static String? _pathFor(CommandContext context) {
    final entry = context.entry;
    final here = context.panel.currentPath;
    if (entry == null || entry.path.isEmpty) {
      return here;
    }
    final directory = entry.isDirectory || (entry.isLink && entry.linkToDirectory);
    return directory ? entry.path : here;
  }
}

/// Вход в объект под курсором.
///
/// Каталог открывается в панели, ссылка разрешается, обычный файл отдаётся
/// системе.
class OpenNodeCommand extends AppCommand {
  OpenNodeCommand();

  static const String commandId = 'panel.open';

  @override
  String get id => commandId;

  @override
  String get label => tr('Open');

  @override
  String get description => tr('Enter a directory or an archive');

  @override
  bool isExecutable(CommandContext context) => context.entry != null && !context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async {
    // Панель сама решает, куда можно войти. То, что каталогом не является, она
    // возвращает обратно — и **на этом всё**.
    //
    // Раньше такой объект уходил системе, тем же `open`, что и `Cmd-O`. Это
    // оказалось неожиданным: `Enter` в файловом менеджере значит «войти», а
    // запускал он чужое приложение — на текстовом файле открывался редактор,
    // которого никто не звал. Отдать файл системе по-прежнему можно, но
    // сказав это прямо: `Cmd-O` (`panel.openWithSystem`).
    await context.panel.enterCurrent();
  }
}

/// Открыть объект средствами системы, не заходя в него.
///
/// Отдельная команда, а не параметр [OpenNodeCommand]: команда обязана
/// работать одинаково, откуда бы её ни вызвали.
class OpenWithSystemCommand extends AppCommand {
  OpenWithSystemCommand({required SystemOpener opener}) : _open = opener;

  final SystemOpener _open;

  static const String commandId = 'panel.openWithSystem';

  @override
  String get id => commandId;

  @override
  String get label => tr('Open with system');

  @override
  String get description => tr('Hand the selected items to the system, without entering them');

  /// «Открыть в Finder», «внешней программой», «по умолчанию» — три способа
  /// назвать одно и то же, и ни одного из них нет в названии.
  @override
  Set<String> get keywords => const {'default application', 'external', 'launch', 'finder', 'explorer'};

  /// Путь уходит внешней программе как есть, поэтому он должен быть настоящим:
  /// у архива и удалённой ФС таких путей не бывает (`OPIF_REALNAMES` в Far —
  /// про то же самое).
  @override
  bool isExecutable(CommandContext context) =>
      context.entry != null && context.panel.source.capabilities.realFileSystem;

  @override
  Future<void> execute(CommandContext context) async {
    if (!context.panel.source.capabilities.realFileSystem) {
      return;
    }
    for (final entry in context.targets) {
      await _open(entry.path);
    }
  }
}

/// На уровень вверх.
class GoUpCommand extends AppCommand {
  static const String commandId = 'panel.up';

  @override
  String get id => commandId;

  @override
  String get label => tr('Up');

  @override
  String get description => tr('Leave for the parent directory');

  @override
  Set<String> get keywords => const {'parent', 'back', 'go up'};

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.canGoUp;

  @override
  Future<void> execute(CommandContext context) => context.panel.goUp();
}

/// В корень провайдера.
class GoToRootCommand extends AppCommand {
  static const String commandId = 'panel.root';

  @override
  String get id => commandId;

  @override
  String get label => tr('Root');

  @override
  String get description => tr('Go to the root of the current source');

  @override
  bool isExecutable(CommandContext context) =>
      !context.panel.busy && context.panel.currentPath != context.panel.source.rootPath;

  @override
  Future<void> execute(CommandContext context) => context.panel.openPath(context.panel.source.rootPath);
}

/// Посчитать размеры всех каталогов текущего каталога.
///
/// Одним нажатием, а не пометкой: помечать десяток каталогов ради их размеров —
/// работа, которую человек делает вместо приложения.
class CalculateSizesCommand extends AppCommand {
  static const String commandId = 'panel.calculateSizes';

  @override
  String get id => commandId;

  @override
  String get label => tr('Sizes');

  @override
  String get description => tr('Measure every directory here, not just the marked ones');

  /// `du` — привычка из терминала, «disk usage» — то же словами.
  @override
  Set<String> get keywords => const {'directory sizes', 'disk usage', 'du', 'measure'};

  /// Занятой панели считать нечего: список ещё читается, и обходить пока некого.
  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.currentPath.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.measureDirectories();
}

/// Перечитать текущий каталог.
class ReloadCommand extends AppCommand {
  static const String commandId = 'panel.reload';

  @override
  String get id => commandId;

  @override
  String get label => tr('Reload');

  @override
  String get description => tr('Read the current directory again');

  @override
  Set<String> get keywords => const {'refresh', 'rescan', 'update'};

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.currentPath.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) => context.panel.reload();
}

/// Показать или спрятать скрытые объекты.
class ToggleHiddenCommand extends AppCommand {
  static const String commandId = 'panel.toggleHidden';

  @override
  String get id => commandId;

  @override
  String get label => tr('Hidden files');

  @override
  String get description => tr('Show or hide the items whose names start with a dot');

  /// «Dotfiles» — то же самое одним словом, и в названии его нет.
  @override
  Set<String> get keywords => const {'dotfiles', 'show hidden', 'invisible'};

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async {
    final showing = !context.panel.showHidden;
    await context.panel.setShowHidden(showing);

    // Сказать вслух: в каталоге без скрытых файлов переключение ничего не
    // меняет на экране, и понять, сработало ли оно, иначе неоткуда.
    context.app.toasts.show(showing ? tr('Show hidden files: On') : tr('Show hidden files: Off'));
  }
}

/// Отмена текущей операции панели.
///
/// Стоит раньше команды сброса пометки: пока панель занята, Esc должен
/// прерывать чтение, а не трогать пометку.
class CancelCommand extends AppCommand {
  static const String commandId = 'panel.cancel';

  @override
  String get id => commandId;

  @override
  // С оговоркой: «Cancel» на кнопке окна — это «Отмена», а здесь «прервать
  // то, чем панель занята» (`docs/spec/localization.md`, §3).
  String get label => tr('Cancel', context: 'panel');

  @override
  String get description => tr('Stop what the panel is doing right now');

  @override
  Set<String> get keywords => const {'stop', 'abort', 'interrupt'};

  @override
  bool isExecutable(CommandContext context) => context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async => context.panel.cancel();
}
