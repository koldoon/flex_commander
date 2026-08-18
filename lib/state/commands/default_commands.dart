import '../../model/os/system_open.dart';
import 'app_command.dart';
import 'command_registry.dart';
import 'file_commands.dart';
import 'help_command.dart';
import 'layout_commands.dart';
import 'navigation_commands.dart';
import 'selection_commands.dart';
import 'transfer_commands.dart';

/// Команды приложения — фабриками, а не экземплярами: на каждый запуск
/// создаётся своя команда, потому что она хранит состояние исполнения.
///
/// Порядок здесь ни на что не влияет: приоритет задают привязки клавиш,
/// а не команды. Зависимости команд приходят параметрами — их подставляет
/// контейнер (`AppContext`), а тесты подменяют своими.
List<CommandFactory> defaultCommands({SystemOpener? opener, CommandRegistry? Function()? registry}) => [
  // Навигация.
  () => MoveCursorUpCommand(),
  () => MoveCursorDownCommand(),
  () => PageUpCommand(),
  () => PageDownCommand(),
  () => GoToFirstNodeCommand(),
  () => GoToLastNodeCommand(),
  () => GoToNameCommand(),
  () => TogglePanelCommand(),
  () => CenterSplitCommand(),
  () => OpenNodeCommand(opener: opener),
  () => OpenWithSystemCommand(opener: opener),
  () => GoUpCommand(),
  () => GoToRootCommand(),
  () => ReloadCommand(),
  () => ToggleHiddenCommand(),
  () => CancelCommand(),

  // Файловые операции.
  () => MakeDirectoryCommand(),
  () => RemoveCommand(),
  () => RemovePermanentlyCommand(),
  () => CopyCommand(),
  () => MoveCommand(),

  // Пометка объектов.
  () => ClearSelectionCommand(),
  () => ToggleMarkCommand(),
  () => SelectAllCommand(),

  // Справка: таблица текущих настроек и привязок клавиш.
  () => HelpCommand(registry: registry),

  // Ещё не реализованные команды: клавиши за ними уже закреплены, кнопки внизу
  // окна показаны и приглушены.
  () => PlaceholderCommand(id: 'app.menu', label: 'Menu'),
  () => PlaceholderCommand(id: 'file.view', label: 'View'),
  () => PlaceholderCommand(id: 'file.edit', label: 'Edit'),
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
  // На macOS `Cmd-H` занят системным меню приложения («Hide APP_NAME»), и до
  // окна нажатие не доходит вовсе. Поэтому основное сочетание — `Cmd-Shift-H`;
  // `Cmd-H` остаётся ради Windows и Linux, где он разбирается как `Ctrl-H`.
  KeyBinding('Cmd-Shift-H', 'panel.toggleHidden'),
  KeyBinding('Cmd-H', 'panel.toggleHidden'),

  // Пометка объектов. Отмена операции идёт раньше сброса пометки.
  KeyBinding('Esc', 'panel.cancel'),
  KeyBinding('Esc', 'panel.selection.clear'),
  KeyBinding('Space', 'panel.selection.toggle'),
  KeyBinding('Ins', 'panel.selection.toggle'),
  KeyBinding('Cmd-A', 'panel.selection.all'),

  // Переход к имени по набранному символу. Стоит последней: любая привязка к
  // конкретной клавише имеет приоритет над «любым символом».
  const KeyBinding.anyCharacter('panel.goToName', characterParam: GoToNameCommand.characterParam),

  // Нижняя панель: подписи кнопок берутся из этих же привязок.
  KeyBinding('F1', 'app.help'),
  KeyBinding('F2', 'app.menu'),
  KeyBinding('F3', 'file.view'),
  KeyBinding('F4', 'file.edit'),
  KeyBinding('F5', 'file.copy'),
  KeyBinding('F6', 'file.move'),
  KeyBinding('F7', 'file.mkdir'),
  // На macOS F-клавиши по умолчанию отданы системе (F7 — «предыдущий трек»),
  // и до приложения нажатие не доходит. Привычное сочетание из Finder работает
  // без настройки клавиатуры.
  KeyBinding('Shift-Cmd-N', 'file.mkdir'),
  KeyBinding('F8', 'file.remove'),
  KeyBinding('Shift-F8', 'file.removePermanently'),
  // F-клавиши на macOS по умолчанию отданы системе, поэтому у удаления есть
  // и привычные сочетания.
  KeyBinding('Cmd-Bsp', 'file.remove'),
  KeyBinding('Shift-Cmd-Bsp', 'file.removePermanently'),
];

CommandRegistry defaultCommandRegistry({SystemOpener? opener}) {
  // Справка показывает содержимое самого реестра, а реестра в этот момент ещё
  // нет: команда получает не его, а способ его спросить — к первому запуску он
  // уже собран.
  late final CommandRegistry registry;
  registry = CommandRegistry(defaultCommands(opener: opener, registry: () => registry), defaultKeyBindings());
  return registry;
}
