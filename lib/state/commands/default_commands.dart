import 'package:fc_api/fc_api.dart';
import 'file_commands.dart';
import 'help_command.dart';
import 'transfer_commands.dart';

/// Команды, ещё не разъехавшиеся по модулям.
///
/// Фабриками, а не экземплярами: на каждый запуск создаётся своя команда,
/// потому что она хранит состояние исполнения. Порядок здесь ни на что не
/// влияет: приоритет задают привязки клавиш, а не команды.
List<AppCommandFactory> defaultCommands({CommandRegistry? Function()? registry}) => [
  // Файловые операции.
  () => MakeDirectoryCommand(),
  () => RemoveCommand(),
  () => RemovePermanentlyCommand(),
  () => CopyCommand(),
  () => MoveCommand(),

  // Справка: таблица текущих настроек и привязок клавиш.
  () => HelpCommand(registry: registry),

  // Ещё не реализованные команды: клавиши за ними уже закреплены, кнопки внизу
  // окна показаны и приглушены.
  () => PlaceholderCommand(id: 'app.menu', label: 'Menu'),
  () => PlaceholderCommand(id: 'file.view', label: 'View'),
  () => PlaceholderCommand(id: 'file.edit', label: 'Edit'),
];

/// Привязки клавиш команд, ещё не разъехавшихся по модулям.
///
/// Порядок важен: он задаёт приоритет. Навигация и пометка со своими клавишами
/// уже живут в модуле `fc_navigation` — здесь остались файловые операции,
/// справка и заглушки.
List<KeyBinding> defaultKeyBindings() => [
  // Курсор.

  // Навигация по дереву.
  // На macOS `Cmd-H` занят системным меню приложения («Hide APP_NAME»), и до
  // окна нажатие не доходит вовсе. Поэтому основное сочетание — `Cmd-Shift-H`;
  // `Cmd-H` остаётся ради Windows и Linux, где он разбирается как `Ctrl-H`.

  // Пометка объектов. Отмена операции идёт раньше сброса пометки.

  // Переход к имени по набранному символу. Стоит последней: любая привязка к
  // конкретной клавише имеет приоритет над «любым символом».

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

CommandRegistry defaultCommandRegistry({CommandErrorHandler? onError}) {
  // Справка показывает содержимое самого реестра, а реестра в этот момент ещё
  // нет: команда получает не его, а способ его спросить — к первому запуску он
  // уже собран.
  late final CommandRegistry registry;
  registry = CommandRegistry(defaultCommands(registry: () => registry), defaultKeyBindings(), onError);
  return registry;
}
