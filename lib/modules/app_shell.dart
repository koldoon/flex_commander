import 'package:fc_api/fc_api.dart';

import '../state/commands/help_command.dart';

/// Оболочка приложения: то, что есть у файлового менеджера всегда.
///
/// Движок файловых операций, справка и обещания клавиш: `F3` и `F4` заняты
/// заглушками, потому что просмотрщик и редактор появятся модулями, а
/// пользователь должен видеть, что место за ними закреплено.
class AppShell implements FcModule {
  const AppShell();

  /// Обещания клавиш: команды за ними появятся модулями, а сами клавиши
  /// заняты уже сейчас. Идентификаторы объявлены здесь — своих классов у
  /// заглушек нет.
  static const String menuCommand = 'app.menu';
  static const String viewCommand = 'file.view';
  static const String editCommand = 'file.edit';

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
    registry.binding(KeyBinding('F1', HelpCommand.commandId));

    // Ещё не реализованное: клавиша закреплена, кнопка показана и приглушена.
    registry.command((context) => PlaceholderCommand(id: menuCommand, label: 'Menu'));
    registry.command((context) => PlaceholderCommand(id: viewCommand, label: 'View'));
    registry.command((context) => PlaceholderCommand(id: editCommand, label: 'Edit'));
    registry.binding(KeyBinding('F2', menuCommand));
    registry.binding(KeyBinding('F3', viewCommand));
    registry.binding(KeyBinding('F4', editCommand));
  }
}
