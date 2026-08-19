import 'package:fc_api/fc_api.dart';

import 'layout_commands.dart';
import 'navigation_commands.dart';
import 'selection_commands.dart';

/// Перемещение по дереву и пометка объектов.
///
/// Всё, чем пользуются руками каждую минуту: курсор, вход в каталог, возврат
/// наверх, перечитывание, пометка. Отдельным модулем — потому что это не
/// «часть ядра», а один из наборов действий: приложение обязано собираться и
/// без него, просто ходить по дереву будет нечем.
class Navigation implements FcModule {
  const Navigation();

  static const String commandId = 'fc.navigation';

  @override
  String get id => commandId;

  @override
  String get title => 'Navigation';

  @override
  void install(FcRegistry registry) {
    // Курсор.
    registry.command((context) => MoveCursorUpCommand());
    registry.command((context) => MoveCursorDownCommand());
    registry.command((context) => PageUpCommand());
    registry.command((context) => PageDownCommand());
    registry.command((context) => GoToFirstNodeCommand());
    registry.command((context) => GoToLastNodeCommand());
    registry.command((context) => GoToNameCommand());

    // Панели и дерево.
    registry.command((context) => TogglePanelCommand());
    registry.command((context) => CenterSplitCommand());
    registry.command((context) => OpenNodeCommand(opener: context.resolve<SystemOpener>()));
    registry.command((context) => OpenWithSystemCommand(opener: context.resolve<SystemOpener>()));
    registry.command((context) => GoUpCommand());
    registry.command((context) => GoToRootCommand());
    registry.command((context) => ReloadCommand());
    registry.command((context) => ToggleHiddenCommand());
    registry.command((context) => CancelCommand());

    // Пометка объектов.
    registry.command((context) => ClearSelectionCommand());
    registry.command((context) => ToggleMarkCommand());
    registry.command((context) => SelectAllCommand());

    _bindKeys(registry);
  }

  /// Клавиши. Порядок задаёт приоритет — он и есть содержание этого метода.
  void _bindKeys(FcRegistry registry) {
    // Курсор.
    registry.binding(KeyBinding('Up', MoveCursorUpCommand.commandId));
    registry.binding(KeyBinding('Down', MoveCursorDownCommand.commandId));
    registry.binding(KeyBinding('PgUp', PageUpCommand.commandId));
    registry.binding(KeyBinding('PgDn', PageDownCommand.commandId));
    registry.binding(KeyBinding('Home', GoToFirstNodeCommand.commandId));
    registry.binding(KeyBinding('Left', GoToFirstNodeCommand.commandId));
    registry.binding(KeyBinding('End', GoToLastNodeCommand.commandId));
    registry.binding(KeyBinding('Right', GoToLastNodeCommand.commandId));

    // Навигация по дереву.
    registry.binding(KeyBinding('Tab', TogglePanelCommand.commandId));
    registry.binding(KeyBinding('Enter', OpenNodeCommand.commandId));
    registry.binding(KeyBinding('Cmd-O', OpenWithSystemCommand.commandId));
    registry.binding(KeyBinding('Bsp', GoUpCommand.commandId));
    registry.binding(KeyBinding('Cmd-Up', GoUpCommand.commandId));
    registry.binding(KeyBinding('Cmd-/', GoToRootCommand.commandId));
    registry.binding(KeyBinding('Cmd-R', ReloadCommand.commandId));
    // На macOS `Cmd-H` занят системным меню приложения («Hide APP_NAME»), и до
    // окна нажатие не доходит вовсе. Поэтому основное сочетание — `Cmd-Shift-H`;
    // `Cmd-H` остаётся ради Windows и Linux, где он разбирается как `Ctrl-H`.
    registry.binding(KeyBinding('Cmd-Shift-H', ToggleHiddenCommand.commandId));
    registry.binding(KeyBinding('Cmd-H', ToggleHiddenCommand.commandId));

    // Пометка объектов. Отмена операции идёт раньше сброса пометки.
    registry.binding(KeyBinding('Esc', CancelCommand.commandId));
    registry.binding(KeyBinding('Esc', ClearSelectionCommand.commandId));
    registry.binding(KeyBinding('Space', ToggleMarkCommand.commandId));
    registry.binding(KeyBinding('Ins', ToggleMarkCommand.commandId));
    registry.binding(KeyBinding('Cmd-A', SelectAllCommand.commandId));

    // Переход к имени по набранному символу. Стоит после привязок к конкретным
    // символам: иначе набор имени перехватывал бы их.
    registry.binding(
      const KeyBinding.anyCharacter(GoToNameCommand.commandId, characterParam: GoToNameCommand.characterParam),
    );
  }
}
