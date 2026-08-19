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

  @override
  String get id => 'fc.navigation';

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
    registry.binding(KeyBinding('Up', 'panel.cursor.up'));
    registry.binding(KeyBinding('Down', 'panel.cursor.down'));
    registry.binding(KeyBinding('PgUp', 'panel.cursor.pageUp'));
    registry.binding(KeyBinding('PgDn', 'panel.cursor.pageDown'));
    registry.binding(KeyBinding('Home', 'panel.cursor.first'));
    registry.binding(KeyBinding('Left', 'panel.cursor.first'));
    registry.binding(KeyBinding('End', 'panel.cursor.last'));
    registry.binding(KeyBinding('Right', 'panel.cursor.last'));

    // Навигация по дереву.
    registry.binding(KeyBinding('Tab', 'app.togglePanel'));
    registry.binding(KeyBinding('Enter', 'panel.open'));
    registry.binding(KeyBinding('Cmd-O', 'panel.openWithSystem'));
    registry.binding(KeyBinding('Bsp', 'panel.up'));
    registry.binding(KeyBinding('Cmd-Up', 'panel.up'));
    registry.binding(KeyBinding('Cmd-/', 'panel.root'));
    registry.binding(KeyBinding('Cmd-R', 'panel.reload'));
    // На macOS `Cmd-H` занят системным меню приложения («Hide APP_NAME»), и до
    // окна нажатие не доходит вовсе. Поэтому основное сочетание — `Cmd-Shift-H`;
    // `Cmd-H` остаётся ради Windows и Linux, где он разбирается как `Ctrl-H`.
    registry.binding(KeyBinding('Cmd-Shift-H', 'panel.toggleHidden'));
    registry.binding(KeyBinding('Cmd-H', 'panel.toggleHidden'));

    // Пометка объектов. Отмена операции идёт раньше сброса пометки.
    registry.binding(KeyBinding('Esc', 'panel.cancel'));
    registry.binding(KeyBinding('Esc', 'panel.selection.clear'));
    registry.binding(KeyBinding('Space', 'panel.selection.toggle'));
    registry.binding(KeyBinding('Ins', 'panel.selection.toggle'));
    registry.binding(KeyBinding('Cmd-A', 'panel.selection.all'));

    // Переход к имени по набранному символу. Стоит после привязок к конкретным
    // символам: иначе набор имени перехватывал бы их.
    registry.binding(const KeyBinding.anyCharacter('panel.goToName', characterParam: GoToNameCommand.characterParam));
  }
}
