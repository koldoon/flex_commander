import 'package:fc_api/fc_api.dart';

import '../state/commands/help_command.dart';

/// Оболочка приложения: то, что есть у файлового менеджера всегда.
///
/// Движок файловых операций, справка и обещания клавиш: `F3` и `F4` заняты
/// заглушками, потому что просмотрщик и редактор появятся модулями, а
/// пользователь должен видеть, что место за ними закреплено.
class AppShell implements FcModule {
  const AppShell();

  @override
  String get id => 'fc.shell';

  @override
  String get title => 'Application shell';

  @override
  void install(FcRegistry registry) {
    // Движок один на приложение: состояния у него нет, а провайдеров узлы
    // приносят с собой — в том числе разных у источника и приёмника.
    registry.service<TreeEditor>((services) => const TreeTransferEngine());

    // Справка показывает содержимое реестра, а реестра во время объявления
    // ещё нет: команда получает не его, а способ его спросить.
    registry.command((context) => HelpCommand(registry: () => context.resolve<CommandRegistry>()));
    registry.binding(KeyBinding('F1', 'app.help'));

    // Ещё не реализованное: клавиша закреплена, кнопка показана и приглушена.
    registry.command((context) => PlaceholderCommand(id: 'app.menu', label: 'Menu'));
    registry.command((context) => PlaceholderCommand(id: 'file.view', label: 'View'));
    registry.command((context) => PlaceholderCommand(id: 'file.edit', label: 'Edit'));
    registry.binding(KeyBinding('F2', 'app.menu'));
    registry.binding(KeyBinding('F3', 'file.view'));
    registry.binding(KeyBinding('F4', 'file.edit'));
  }
}
