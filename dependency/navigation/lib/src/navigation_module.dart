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
  void install(FcRegistrar registrar) {
    // Курсор.
    registrar.command((context) => MoveCursorUpCommand());
    registrar.command((context) => MoveCursorDownCommand());
    registrar.command((context) => PageUpCommand());
    registrar.command((context) => PageDownCommand());
    registrar.command((context) => GoToFirstNodeCommand());
    registrar.command((context) => GoToLastNodeCommand());
    registrar.command((context) => GoToNameCommand());

    // Панели и дерево.
    registrar.command((context) => TogglePanelCommand());
    registrar.command((context) => CenterSplitCommand());
    registrar.command((context) => OpenNodeCommand(opener: context.resolve<SystemOpener>()));
    registrar.command((context) => OpenWithSystemCommand(opener: context.resolve<SystemOpener>()));
    registrar.command((context) => GoUpCommand());
    registrar.command((context) => GoToRootCommand());
    registrar.command((context) => ReloadCommand());
    registrar.command((context) => ToggleHiddenCommand());
    registrar.command((context) => CancelCommand());

    // Пометка объектов.
    registrar.command((context) => ClearSelectionCommand());
    registrar.command((context) => ToggleMarkCommand());
    registrar.command((context) => SelectAllCommand());

    _bindKeys(registrar);
  }

  /// Клавиши. Порядок задаёт приоритет — он и есть содержание этого метода.
  void _bindKeys(FcRegistrar registrar) {
    // Курсор.
    registrar.binding(KeyBinding('Up', 'panel.cursor.up'));
    registrar.binding(KeyBinding('Down', 'panel.cursor.down'));
    registrar.binding(KeyBinding('PgUp', 'panel.cursor.pageUp'));
    registrar.binding(KeyBinding('PgDn', 'panel.cursor.pageDown'));
    registrar.binding(KeyBinding('Home', 'panel.cursor.first'));
    registrar.binding(KeyBinding('Left', 'panel.cursor.first'));
    registrar.binding(KeyBinding('End', 'panel.cursor.last'));
    registrar.binding(KeyBinding('Right', 'panel.cursor.last'));

    // Навигация по дереву.
    registrar.binding(KeyBinding('Tab', 'app.togglePanel'));
    registrar.binding(KeyBinding('Enter', 'panel.open'));
    registrar.binding(KeyBinding('Cmd-O', 'panel.openWithSystem'));
    registrar.binding(KeyBinding('Bsp', 'panel.up'));
    registrar.binding(KeyBinding('Cmd-Up', 'panel.up'));
    registrar.binding(KeyBinding('Cmd-/', 'panel.root'));
    registrar.binding(KeyBinding('Cmd-R', 'panel.reload'));
    // На macOS `Cmd-H` занят системным меню приложения («Hide APP_NAME»), и до
    // окна нажатие не доходит вовсе. Поэтому основное сочетание — `Cmd-Shift-H`;
    // `Cmd-H` остаётся ради Windows и Linux, где он разбирается как `Ctrl-H`.
    registrar.binding(KeyBinding('Cmd-Shift-H', 'panel.toggleHidden'));
    registrar.binding(KeyBinding('Cmd-H', 'panel.toggleHidden'));

    // Пометка объектов. Отмена операции идёт раньше сброса пометки.
    registrar.binding(KeyBinding('Esc', 'panel.cancel'));
    registrar.binding(KeyBinding('Esc', 'panel.selection.clear'));
    registrar.binding(KeyBinding('Space', 'panel.selection.toggle'));
    registrar.binding(KeyBinding('Ins', 'panel.selection.toggle'));
    registrar.binding(KeyBinding('Cmd-A', 'panel.selection.all'));

    // Переход к имени по набранному символу. Стоит после привязок к конкретным
    // символам: иначе набор имени перехватывал бы их.
    registrar.binding(const KeyBinding.anyCharacter('panel.goToName', characterParam: GoToNameCommand.characterParam));
  }
}
