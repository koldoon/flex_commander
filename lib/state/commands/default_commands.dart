import 'app_command.dart';
import 'command_registry.dart';
import 'navigation_commands.dart';
import 'selection_commands.dart';

/// Набор команд приложения.
///
/// Порядок важен: он задаёт приоритет при разборе нажатия. Специализированные
/// команды идут раньше общих, поэтому `Esc` во время чтения каталога отменяет
/// операцию, а в остальное время снимает пометку.
List<AppCommand> defaultCommands() => [
  // Навигация.
  MoveCursorCommand(),
  PageCursorCommand(),
  CursorEdgeCommand(),
  TogglePanelCommand(),
  OpenNodeCommand(),
  GoUpCommand(),
  GoToRootCommand(),
  ReloadCommand(),
  ToggleHiddenCommand(),
  ToggleThemeCommand(),

  // Пометка объектов.
  CancelCommand(),
  ClearSelectionCommand(),
  ToggleMarkCommand(),
  SelectAllCommand(),

  // Файловые операции появятся на следующем этапе: слоты заняты, кнопки
  // показаны и приглушены, связка «кнопка ↔ команда ↔ клавиша» уже работает.
  PlaceholderCommand(id: 'app.help', label: 'Help', functionKey: FunctionKeySlot.f1),
  PlaceholderCommand(id: 'app.menu', label: 'Menu', functionKey: FunctionKeySlot.f2),
  PlaceholderCommand(id: 'file.view', label: 'View', functionKey: FunctionKeySlot.f3),
  PlaceholderCommand(id: 'file.edit', label: 'Edit', functionKey: FunctionKeySlot.f4),
  PlaceholderCommand(id: 'file.copy', label: 'Copy', functionKey: FunctionKeySlot.f5),
  PlaceholderCommand(id: 'file.move', label: 'Move', functionKey: FunctionKeySlot.f6),
  PlaceholderCommand(id: 'file.mkdir', label: 'Mk Dir', functionKey: FunctionKeySlot.f7),
  PlaceholderCommand(id: 'file.remove', label: 'Delete', functionKey: FunctionKeySlot.f8),
];

CommandRegistry defaultCommandRegistry() => CommandRegistry(defaultCommands());
