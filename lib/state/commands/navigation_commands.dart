import '../../model/os/system_open.dart';
import '../../model/settings/app_settings.dart';
import 'app_command.dart';

/// Перемещение курсора на строку. Направление приходит параметром привязки,
/// поэтому обе клавиши обслуживает одна команда.
class MoveCursorCommand extends AppCommand {
  static const String deltaParameter = 'delta';

  @override
  String get id => 'panel.cursor.move';

  @override
  String get label => 'Move cursor';

  @override
  List<KeyBinding> get bindings => [
    KeyBinding('Up', parameters: const {deltaParameter: -1}),
    KeyBinding('Down', parameters: const {deltaParameter: 1}),
  ];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async {
    context.panel.moveCursor(context.parameter<int>(deltaParameter) ?? 0);
  }
}

/// Перемещение курсора на страницу — по числу видимых строк.
class PageCursorCommand extends AppCommand {
  static const String directionParameter = 'direction';

  @override
  String get id => 'panel.cursor.page';

  @override
  String get label => 'Page';

  @override
  List<KeyBinding> get bindings => [
    KeyBinding('PgUp', parameters: const {directionParameter: -1}),
    KeyBinding('PgDn', parameters: const {directionParameter: 1}),
  ];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async {
    context.panel.moveCursorPage(context.parameter<int>(directionParameter) ?? 0);
  }
}

/// Курсор в начало и в конец списка.
///
/// Стрелки влево и вправо заняты именно этим — панели переключаются только
/// Tab (решение референса: `GoToFirstNodeCommand` / `GoToLastNodeCommand`).
class CursorEdgeCommand extends AppCommand {
  static const String edgeParameter = 'edge';
  static const String first = 'first';
  static const String last = 'last';

  @override
  String get id => 'panel.cursor.edge';

  @override
  String get label => 'First / last';

  @override
  List<KeyBinding> get bindings => [
    KeyBinding('Home', parameters: const {edgeParameter: first}),
    KeyBinding('Left', parameters: const {edgeParameter: first}),
    KeyBinding('End', parameters: const {edgeParameter: last}),
    KeyBinding('Right', parameters: const {edgeParameter: last}),
  ];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async {
    if (context.parameter<String>(edgeParameter) == last) {
      context.panel.setCursorToLast();
    } else {
      context.panel.setCursorToFirst();
    }
  }
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
/// системе. `Cmd-O` открывает системой что угодно, включая каталог.
class OpenNodeCommand extends AppCommand {
  OpenNodeCommand({SystemOpener? opener}) : _open = opener ?? openWithSystem;

  static const String forceOpenParameter = 'forceOpen';

  final SystemOpener _open;

  @override
  String get id => 'panel.open';

  @override
  String get label => 'Open';

  @override
  List<KeyBinding> get bindings => [
    KeyBinding('Enter'),
    KeyBinding('Cmd-O', parameters: const {forceOpenParameter: true}),
  ];

  @override
  bool isExecutable(CommandContext context) => context.node != null && !context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async {
    final node = context.node;
    if (node == null) {
      return;
    }

    if (context.parameter<bool>(forceOpenParameter) ?? false) {
      await _open(node.pathString);
      return;
    }

    // Панель сама решает, куда можно войти, и возвращает то, что каталогом
    // не является: такой объект открывает система.
    final rest = await context.panel.enterCurrent();
    if (rest != null) {
      await _open(rest.pathString);
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
  String get label => 'Hidden';

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

/// Переключение темы оформления. Кнопкой не показывается — только клавишами.
class ToggleThemeCommand extends AppCommand {
  @override
  String get id => 'app.toggleTheme';

  @override
  String get label => 'Theme';

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
