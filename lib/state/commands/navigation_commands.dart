import '../../model/os/system_open.dart';
import '../../model/tree/fs_node.dart';
import '../../model/settings/app_settings.dart';
import 'app_command.dart';

/// Курсор на строку вверх.
class MoveCursorUpCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.up';

  @override
  String get label => 'Cursor up';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.moveCursor(-1);
}

/// Курсор на строку вниз.
class MoveCursorDownCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.down';

  @override
  String get label => 'Cursor down';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.moveCursor(1);
}

/// Курсор на первый объект, чьё имя начинается с заданного символа.
///
/// Символ приходит параметром, а не из события клавиатуры: команде всё равно,
/// набрали его на клавиатуре, выбрали в списке команд или подставил сценарий.
class GoToNameCommand extends AppCommand {
  /// Символ, с которого начинается имя.
  static const String characterParam = 'character';

  @override
  String get id => 'panel.goToName';

  @override
  String get label => 'Go to name';

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async {
    final character = param<String>(characterParam)?.toLowerCase() ?? '';
    if (character.isEmpty) {
      return;
    }

    final panel = context.panel;
    final nodes = panel.nodes;

    // Поиск идёт от курсора вниз и по кругу: повторное нажатие той же буквы
    // переходит к следующему такому имени, а не топчется на первом.
    for (var offset = 1; offset <= nodes.length; offset++) {
      final index = (panel.cursorIndex + offset) % nodes.length;
      final node = nodes[index];
      // «..» — это не имя файла.
      if (node is ParentDirNode) {
        continue;
      }
      if (node.name.toLowerCase().startsWith(character)) {
        panel.setCursorIndex(index);
        return;
      }
    }
  }
}

/// Курсор на страницу вверх — по числу видимых строк.
class PageUpCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.pageUp';

  @override
  String get label => 'Page up';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.moveCursorPage(-1);
}

/// Курсор на страницу вниз.
class PageDownCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.pageDown';

  @override
  String get label => 'Page down';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.moveCursorPage(1);
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
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.setCursorToFirst();
}

/// Курсор на последний объект списка.
class GoToLastNodeCommand extends AppCommand {
  @override
  String get id => 'panel.cursor.last';

  @override
  String get label => 'Last item';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.setCursorToLast();
}

/// Переключение активной панели.
class TogglePanelCommand extends AppCommand {
  @override
  String get id => 'app.togglePanel';

  @override
  String get label => 'Switch panel';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() async => context.app.toggleActivePanel();
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
  bool isExecutable(CommandContext context) => context.node != null && !context.panel.busy;

  @override
  Future<void> execute() async {
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
  bool isExecutable(CommandContext context) => context.node != null;

  @override
  Future<void> execute() async {
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
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.directory?.parentDirectory != null;

  @override
  Future<void> execute() => context.panel.goUp();
}

/// В корень провайдера.
class GoToRootCommand extends AppCommand {
  @override
  String get id => 'panel.root';

  @override
  String get label => 'Root';

  @override
  bool isExecutable(CommandContext context) =>
      !context.panel.busy && context.panel.directory != context.panel.provider.rootDirectory;

  @override
  Future<void> execute() => context.panel.open(context.panel.provider.rootDirectory);
}

/// Перечитать текущий каталог.
class ReloadCommand extends AppCommand {
  @override
  String get id => 'panel.reload';

  @override
  String get label => 'Reload';

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.directory != null;

  @override
  Future<void> execute() => context.panel.reload();
}

/// Показать или спрятать скрытые объекты.
class ToggleHiddenCommand extends AppCommand {
  @override
  String get id => 'panel.toggleHidden';

  @override
  String get label => 'Hidden files';

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy;

  @override
  Future<void> execute() => context.panel.setShowHidden(!context.panel.showHidden);
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
  bool isExecutable(CommandContext context) => context.panel.busy;

  @override
  Future<void> execute() async => context.panel.cancel();
}

/// Переключение темы оформления. Кнопкой не показывается — только клавишами
/// и из списка команд.
class ToggleThemeCommand extends AppCommand {
  @override
  String get id => 'app.toggleTheme';

  @override
  String get label => 'Toggle theme';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() async {
    final app = context.app;
    app.setThemeMode(app.themeMode == AppThemeMode.dark ? AppThemeMode.light : AppThemeMode.dark);
  }
}
