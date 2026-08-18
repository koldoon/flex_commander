import 'package:fc_api/fc_api.dart';
import 'help_command.dart';

/// Команды, ещё не разъехавшиеся по модулям.
///
/// Фабриками, а не экземплярами: на каждый запуск создаётся своя команда,
/// потому что она хранит состояние исполнения. Порядок здесь ни на что не
/// влияет: приоритет задают привязки клавиш, а не команды.
List<AppCommandFactory> defaultCommands({CommandRegistry? Function()? registry}) => [
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
  // Нижняя панель: подписи кнопок берутся из этих же привязок.
  KeyBinding('F1', 'app.help'),
  KeyBinding('F2', 'app.menu'),
  // Просмотр и правка — заглушки: клавиша закреплена, кнопка показана и
  // приглушена. Появятся они модулями, как и всё остальное.
  KeyBinding('F3', 'file.view'),
  KeyBinding('F4', 'file.edit'),
];

CommandRegistry defaultCommandRegistry({CommandErrorHandler? onError}) {
  // Справка показывает содержимое самого реестра, а реестра в этот момент ещё
  // нет: команда получает не его, а способ его спросить — к первому запуску он
  // уже собран.
  late final CommandRegistry registry;
  registry = CommandRegistry(defaultCommands(registry: () => registry), defaultKeyBindings(), onError);
  return registry;
}
