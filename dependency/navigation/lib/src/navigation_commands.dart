import 'package:fc_api/fc_api.dart';

/// Курсор на строку вверх.
class MoveCursorUpCommand extends AppCommand {
  static const String commandId = 'panel.cursor.up';

  @override
  String get id => commandId;

  @override
  String get label => 'Cursor up';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.moveCursor(-1);
}

/// Курсор на строку вниз.
class MoveCursorDownCommand extends AppCommand {
  static const String commandId = 'panel.cursor.down';

  @override
  String get id => commandId;

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

  static const String commandId = 'panel.goToName';

  @override
  String get id => commandId;

  @override
  String get label => 'Go to name';

  @override
  String get description => 'Jump to the first item starting with the typed letter';

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
  static const String commandId = 'panel.cursor.pageUp';

  @override
  String get id => commandId;

  @override
  String get label => 'Page up';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.moveCursorPage(-1);
}

/// Курсор на страницу вниз.
class PageDownCommand extends AppCommand {
  static const String commandId = 'panel.cursor.pageDown';

  @override
  String get id => commandId;

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
  static const String commandId = 'panel.cursor.first';

  @override
  String get id => commandId;

  @override
  String get label => 'First item';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.setCursorToFirst();
}

/// Курсор на последний объект списка.
class GoToLastNodeCommand extends AppCommand {
  static const String commandId = 'panel.cursor.last';

  @override
  String get id => commandId;

  @override
  String get label => 'Last item';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.setCursorToLast();
}

/// Переключение активной панели.
class TogglePanelCommand extends AppCommand {
  static const String commandId = 'app.togglePanel';

  @override
  String get id => commandId;

  @override
  String get label => 'Switch panel';

  @override
  String get description => 'Make the other panel active';

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
  OpenNodeCommand({required SystemOpener opener}) : _open = opener;

  final SystemOpener _open;

  static const String commandId = 'panel.open';

  @override
  String get id => commandId;

  @override
  String get label => 'Open';

  @override
  String get description => 'Enter a directory or an archive; other files go to the system';

  @override
  bool isExecutable(CommandContext context) => context.node != null && !context.panel.busy;

  @override
  Future<void> execute() async {
    // Панель сама решает, куда можно войти, и возвращает то, что каталогом
    // не является: такой объект открывает система.
    final rest = await context.panel.enterCurrent();
    if (rest == null) {
      return;
    }
    // Отдавать системе можно только настоящий путь: внутри архива или на
    // сервере открывать нечего, там понадобится свой просмотрщик (F3).
    if (rest.provider.capabilities.realFileSystem) {
      await _open(rest.pathString);
    }
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
  String get label => 'Open with system';

  @override
  String get description => 'Hand the selected items to the system, without entering them';

  /// Путь уходит внешней программе как есть, поэтому он должен быть настоящим:
  /// у архива и удалённой ФС таких путей не бывает (`OPIF_REALNAMES` в Far —
  /// про то же самое).
  @override
  bool isExecutable(CommandContext context) {
    final node = context.node;
    return node != null && node.provider.capabilities.realFileSystem;
  }

  @override
  Future<void> execute() async {
    for (final node in context.targets) {
      if (node.provider.capabilities.realFileSystem) {
        await _open(node.pathString);
      }
    }
  }
}

/// На уровень вверх.
class GoUpCommand extends AppCommand {
  static const String commandId = 'panel.up';

  @override
  String get id => commandId;

  @override
  String get label => 'Up';

  @override
  String get description => 'Leave for the parent directory';

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.directory?.parentDirectory != null;

  @override
  Future<void> execute() => context.panel.goUp();
}

/// В корень провайдера.
class GoToRootCommand extends AppCommand {
  static const String commandId = 'panel.root';

  @override
  String get id => commandId;

  @override
  String get label => 'Root';

  @override
  String get description => 'Go to the root of the current source';

  @override
  bool isExecutable(CommandContext context) =>
      !context.panel.busy && context.panel.directory != context.panel.provider.rootDirectory;

  @override
  Future<void> execute() => context.panel.open(context.panel.provider.rootDirectory);
}

/// Перечитать текущий каталог.
class ReloadCommand extends AppCommand {
  static const String commandId = 'panel.reload';

  @override
  String get id => commandId;

  @override
  String get label => 'Reload';

  @override
  String get description => 'Read the current directory again';

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy && context.panel.directory != null;

  @override
  Future<void> execute() => context.panel.reload();
}

/// Показать или спрятать скрытые объекты.
class ToggleHiddenCommand extends AppCommand {
  static const String commandId = 'panel.toggleHidden';

  @override
  String get id => commandId;

  @override
  String get label => 'Hidden files';

  @override
  String get description => 'Show or hide the items whose names start with a dot';

  @override
  bool isExecutable(CommandContext context) => !context.panel.busy;

  @override
  Future<void> execute() async {
    final showing = !context.panel.showHidden;
    await context.panel.setShowHidden(showing);

    // Сказать вслух: в каталоге без скрытых файлов переключение ничего не
    // меняет на экране, и понять, сработало ли оно, иначе неоткуда.
    context.app.toasts.show('Show hidden files: ${showing ? 'On' : 'Off'}');
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
  String get label => 'Cancel';

  @override
  String get description => 'Stop what the panel is doing right now';

  @override
  bool isExecutable(CommandContext context) => context.panel.busy;

  @override
  Future<void> execute() async => context.panel.cancel();
}
