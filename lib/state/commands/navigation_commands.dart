import '../../model/os/system_open.dart';
import '../../model/settings/app_settings.dart';
import 'app_command.dart';

/// Курсор на строку вверх.
class MoveCursorUpCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.up';

  @override
  String get label => 'Cursor up';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Up')];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.moveCursor(-1);
}

/// Курсор на строку вниз.
class MoveCursorDownCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.down';

  @override
  String get label => 'Cursor down';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Down')];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.moveCursor(1);
}

/// Курсор на страницу вверх — по числу видимых строк.
class PageUpCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.pageUp';

  @override
  String get label => 'Page up';

  @override
  List<KeyBinding> get bindings => [KeyBinding('PgUp')];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.moveCursorPage(-1);
}

/// Курсор на страницу вниз.
class PageDownCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.pageDown';

  @override
  String get label => 'Page down';

  @override
  List<KeyBinding> get bindings => [KeyBinding('PgDn')];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.moveCursorPage(1);
}

/// Курсор на первый объект списка.
///
/// Стрелка влево занята именно этим — панели переключаются только Tab
/// (решение референса: `GoToFirstNodeCommand`).
class GoToFirstNodeCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.first';

  @override
  String get label => 'First item';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Home'), KeyBinding('Left')];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.setCursorToFirst();
}

/// Курсор на последний объект списка.
class GoToLastNodeCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.last';

  @override
  String get label => 'Last item';

  @override
  List<KeyBinding> get bindings => [KeyBinding('End'), KeyBinding('Right')];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.setCursorToLast();
}

/// Переключение активной панели.
class TogglePanelCommand extends AppCommand {
  @override
  String get id => 'app.togglePanel';

  @override
  String get label => 'Switch panel';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Tab')];

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async => context.app.toggleActivePanel();
}

/// Вход в объект под курсором.
///
/// Каталог открывается в панели, ссылка разрешается, обычный файл отдаётся
/// системе.
class OpenNodeCommand extends AppCommand {
  OpenNodeCommand({SystemOpener? opener}) : _open = opener ?? openWithSystem;

  final SystemOpener _open;

  @override
  String get id => 'panel.open';

  @override
  String get label => 'Open';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Enter')];

  @override
  bool isExecutable(CommandContext context) => context.node != null && !context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async {
    // Панель сама решает, куда можно войти, и возвращает то, что каталогом
    // не является: такой объект открывает система.
    final rest = await context.panel.enterCurrent();
    if (rest != null) {
      await _open(rest.pathString);
    }
  }
}

/// Открыть объект средствами системы, не заходя в него.
///
/// Отдельная команда, а не параметр [OpenNodeCommand]: команда обязана
/// работать одинаково, откуда бы её ни вызвали.
class OpenWithSystemCommand extends AppCommand {
  OpenWithSystemCommand({SystemOpener? opener}) : _open = opener ?? openWithSystem;

  final SystemOpener _open;

  @override
  String get id => 'panel.openWithSystem';

  @override
  String get label => 'Open with system';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Cmd-O')];

  @override
  bool isExecutable(CommandContext context) => context.node != null;

  @override
  Future<void> execute(CommandContext context) async {
    for (final node in context.targets) {
      await _open(node.pathString);
    }
  }
}

/// На уровень вверх.
class GoUpCommand extends AppCommand {
  @override
  String get id => 'panel.up';

  @override
  String get label => 'Up';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Bsp'), KeyBinding('Cmd-Up')];

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.directory?.parentDirectory != null;

  @override
  Future<void> execute(CommandContext context) => context.panel.goUp();
}

/// В корень провайдера.
class GoToRootCommand extends AppCommand {
  @override
  String get id => 'panel.root';

  @override
  String get label => 'Root';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Cmd-/')];

  @override
  bool isExecutable(CommandContext context) =>
      !context.panel.busy && context.panel.directory != context.panel.provider.rootDirectory;

  @override
  Future<void> execute(CommandContext context) => context.panel.open(context.panel.provider.rootDirectory);
}

/// Перечитать текущий каталог.
class ReloadCommand extends AppCommand {
  @override
  String get id => 'panel.reload';

  @override
  String get label => 'Reload';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Cmd-R')];

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.directory != null;

  @override
  Future<void> execute(CommandContext context) => context.panel.reload();
}

/// Показать или спрятать скрытые объекты.
class ToggleHiddenCommand extends AppCommand {
  @override
  String get id => 'panel.toggleHidden';

  @override
  String get label => 'Hidden files';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Cmd-H')];

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy;

  @override
  Future<void> execute(CommandContext context) => context.panel.setShowHidden(!context.panel.showHidden);
}

/// Отмена текущей операции панели.
///
/// Стоит раньше команды сброса пометки: пока панель занята, Esc должен
/// прерывать чтение, а не трогать пометку.
class CancelCommand extends AppCommand {
  @override
  String get id => 'panel.cancel';

  @override
  String get label => 'Cancel';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Esc')];

  @override
  bool isExecutable(CommandContext context) => context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async => context.panel.cancel();
}

/// Переключение темы оформления. Кнопкой не показывается — только клавишами
/// и из списка команд.
class ToggleThemeCommand extends AppCommand {
  @override
  String get id => 'app.toggleTheme';

  @override
  String get label => 'Toggle theme';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Cmd-T')];

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    app.setThemeMode(app.themeMode == AppThemeMode.dark ? AppThemeMode.light : AppThemeMode.dark);
  }
}
