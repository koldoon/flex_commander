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
  void install(FcRegistrar registrar) {
    // Движок один на приложение: состояния у него нет, а провайдеров узлы
    // приносят с собой — в том числе разных у источника и приёмника.
    registrar.service<TreeEditor>((services) => const TreeTransferEngine());

    // Справка показывает содержимое реестра, а реестра во время объявления
    // ещё нет: команда получает не его, а способ его спросить.
    registrar.command((context) => HelpCommand(registry: () => context.resolve<CommandRegistry>()));
    registrar.binding(KeyBinding('F1', 'app.help'));

    // Ещё не реализованное: клавиша закреплена, кнопка показана и приглушена.
    registrar.command((context) => PlaceholderCommand(id: 'app.menu', label: 'Menu'));
    registrar.command((context) => PlaceholderCommand(id: 'file.view', label: 'View'));
    registrar.command((context) => PlaceholderCommand(id: 'file.edit', label: 'Edit'));
    registrar.binding(KeyBinding('F2', 'app.menu'));
    registrar.binding(KeyBinding('F3', 'file.view'));
    registrar.binding(KeyBinding('F4', 'file.edit'));
  }
}
