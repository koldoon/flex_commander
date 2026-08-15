import 'app_command.dart';
import 'command_registry.dart';
import 'navigation_commands.dart';
import 'selection_commands.dart';

/// Команды приложения.
///
/// Порядок здесь ни на что не влияет: приоритет задают привязки клавиш,
/// а не команды.
List<AppCommand> defaultCommands() => [
  // Навигация.
  MoveCursorUpCommand(),
  MoveCursorDownCommand(),
  PageUpCommand(),
  PageDownCommand(),
  GoToFirstNodeCommand(),
  GoToLastNodeCommand(),
  TogglePanelCommand(),
  OpenNodeCommand(),
  OpenWithSystemCommand(),
  GoUpCommand(),
  GoToRootCommand(),
  ReloadCommand(),
  ToggleHiddenCommand(),
  ToggleThemeCommand(),
  CancelCommand(),

  // Пометка объектов.
  ClearSelectionCommand(),
  ToggleMarkCommand(),
  SelectAllCommand(),

  // Файловые операции появятся на следующем этапе: клавиши за ними уже
  // закреплены, кнопки внизу окна показаны и приглушены.
  PlaceholderCommand(id: 'app.help', label: 'Help'),
  PlaceholderCommand(id: 'app.menu', label: 'Menu'),
  PlaceholderCommand(id: 'file.view', label: 'View'),
  PlaceholderCommand(id: 'file.edit', label: 'Edit'),
  PlaceholderCommand(id: 'file.copy', label: 'Copy'),
  PlaceholderCommand(id: 'file.move', label: 'Move'),
  PlaceholderCommand(id: 'file.mkdir', label: 'Mk Dir'),
  PlaceholderCommand(id: 'file.remove', label: 'Delete'),
];

/// Привязки клавиш по умолчанию.
///
/// Порядок важен: он задаёт приоритет. `Esc` стоит дважды — пока панель занята,
/// нажатие достаётся отмене операции, а в остальное время снимает пометку.
/// Позже этот список станет основой для пользовательских настроек: заменить
/// привязку можно будет, не трогая команды.
List<KeyBinding> defaultKeyBindings() => [
  // Курсор.
  KeyBinding('Up', 'panel.cursor.up'),
  KeyBinding('Down', 'panel.cursor.down'),
  KeyBinding('PgUp', 'panel.cursor.pageUp'),
  KeyBinding('PgDn', 'panel.cursor.pageDown'),
  KeyBinding('Home', 'panel.cursor.first'),
  KeyBinding('Left', 'panel.cursor.first'),
  KeyBinding('End', 'panel.cursor.last'),
  KeyBinding('Right', 'panel.cursor.last'),

  // Навигация по дереву.
  KeyBinding('Tab', 'app.togglePanel'),
  KeyBinding('Enter', 'panel.open'),
  KeyBinding('Cmd-O', 'panel.openWithSystem'),
  KeyBinding('Bsp', 'panel.up'),
  KeyBinding('Cmd-Up', 'panel.up'),
  KeyBinding('Cmd-/', 'panel.root'),
  KeyBinding('Cmd-R', 'panel.reload'),
  KeyBinding('Cmd-H', 'panel.toggleHidden'),
  KeyBinding('Cmd-T', 'app.toggleTheme'),

  // Пометка объектов. Отмена операции идёт раньше сброса пометки.
  KeyBinding('Esc', 'panel.cancel'),
  KeyBinding('Esc', 'panel.selection.clear'),
  KeyBinding('Space', 'panel.selection.toggle'),
  KeyBinding('Ins', 'panel.selection.toggle'),
  KeyBinding('Cmd-A', 'panel.selection.all'),

  // Нижняя панель: подписи кнопок берутся из этих же привязок.
  KeyBinding('F1', 'app.help'),
  KeyBinding('F2', 'app.menu'),
  KeyBinding('F3', 'file.view'),
  KeyBinding('F4', 'file.edit'),
  KeyBinding('F5', 'file.copy'),
  KeyBinding('F6', 'file.move'),
  KeyBinding('F7', 'file.mkdir'),
  KeyBinding('F8', 'file.remove'),
];

CommandRegistry defaultCommandRegistry() => CommandRegistry(defaultCommands(), defaultKeyBindings());
