import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'layout_commands.dart';
import 'mask_selection_commands.dart';
import 'navigation_settings.dart';
import 'navigation_commands.dart';
import 'open_path_command.dart';
import 'quick_search_commands.dart';
import 'quick_search_state.dart';
import 'quick_search_view.dart';
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
    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    NavigationSettings settingsOf() => settings.section(NavigationSettings.new);

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
    registry.command((context) => OpenPathCommand(settings: settingsOf, save: settings.save));
    registry.command((context) => SelectByMaskCommand(settings: settingsOf, save: settings.save));
    registry.command((context) => DeselectByMaskCommand(settings: settingsOf, save: settings.save));
    registry.command((context) => GoToRootCommand());
    registry.command((context) => ReloadCommand());
    registry.command((context) => ToggleHiddenCommand());
    registry.command((context) => CancelCommand());

    // Пометка объектов.
    registry.command((context) => ClearSelectionCommand());
    registry.command((context) => ToggleMarkCommand());
    registry.command((context) => SelectAllCommand());
    registry.command((context) => SelectFilesCommand());
    registry.view<QuickSearchState>((context, state) => QuickSearchView(state: state));
    registry.command((context) => QuickSearchCommand());
    registry.command((context) => QuickSearchTypeCommand());
    registry.command((context) => QuickSearchEraseCommand());
    registry.command((context) => QuickSearchStopCommand());

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.integer(
          'recentPathsLimit',
          defaultValue: NavigationSettings.defaultLimit,
          title: 'Address history',
          unit: 'entries',
          min: 0,
          max: 500,
          description: 'How many visited addresses the Address window remembers',
          read: () => settingsOf().recentPathsLimit,
          write: (value) => settingsOf().recentPathsLimit = value,
        ),
      ], save: settings.save),
    );

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

    // Размеры всех каталогов — как в Total Commander.
    registry.command((context) => CalculateSizesCommand());
    registry.binding(KeyBinding('Alt-Shift-Enter', CalculateSizesCommand.commandId));
    // Стирание в быстром поиске — **раньше** перехода наверх: пока полоса
    // набора на экране, `Bsp` принадлежит ей целиком, и стёртый до конца
    // образец клавишу не отпускает. Невыполнимо только когда режима нет вовсе,
    // и тогда `Bsp` уводит наверх, как и всегда.
    registry.binding(KeyBinding('Bsp', QuickSearchEraseCommand.commandId));
    registry.binding(KeyBinding('Bsp', GoUpCommand.commandId));
    registry.binding(KeyBinding('Cmd-Up', GoUpCommand.commandId));
    registry.binding(KeyBinding('Cmd-/', GoToRootCommand.commandId));

    // Произвольный путь — по клавише на каждую панель, как выбор диска в
    // Norton Commander. Команда одна: какая панель, приходит параметром.
    registry.binding(
      KeyBinding(
        'Cmd-F1',
        OpenPathCommand.commandId,
        parameters: {OpenPathCommand.panelParam: OpenPathCommand.leftPanel},
      ),
    );
    registry.binding(
      KeyBinding(
        'Cmd-F2',
        OpenPathCommand.commandId,
        parameters: {OpenPathCommand.panelParam: OpenPathCommand.rightPanel},
      ),
    );
    registry.binding(KeyBinding('Cmd-R', ReloadCommand.commandId));
    // На macOS `Cmd-H` занят системным меню приложения («Hide APP_NAME»), и до
    // окна нажатие не доходит вовсе. Поэтому основное сочетание — `Cmd-Shift-H`;
    // `Cmd-H` остаётся ради Windows и Linux, где он разбирается как `Ctrl-H`.
    registry.binding(KeyBinding('Cmd-Shift-H', ToggleHiddenCommand.commandId));
    registry.binding(KeyBinding('Cmd-H', ToggleHiddenCommand.commandId));

    // Быстрый поиск — из `mc`. Его `Esc` и `Backspace` идут **раньше** всех
    // прочих: пока набирают имя, эти клавиши принадлежат набору, а невыполнимы
    // они ровно тогда, когда режим выключен.
    registry.binding(KeyBinding('Ctrl-S', QuickSearchCommand.commandId));
    registry.binding(KeyBinding('Esc', QuickSearchStopCommand.commandId));
    registry.binding(
      const KeyBinding.anyCharacter(
        QuickSearchTypeCommand.commandId,
        characterParam: QuickSearchTypeCommand.characterParam,
      ),
    );

    // Пометка объектов. Отмена операции идёт раньше сброса пометки.
    registry.binding(KeyBinding('Esc', CancelCommand.commandId));
    registry.binding(KeyBinding('Esc', ClearSelectionCommand.commandId));
    registry.binding(KeyBinding('Space', ToggleMarkCommand.commandId));
    registry.binding(KeyBinding('Ins', ToggleMarkCommand.commandId));
    registry.binding(KeyBinding('Cmd-A', SelectAllCommand.commandId));
    registry.binding(KeyBinding('Cmd-Shift-A', SelectFilesCommand.commandId));
    // Пометка по маске. На маке `+` — это `Shift-=`: отдельной клавиши `+` на
    // основной клавиатуре нет, а на цифровом блоке есть своя. В справке пишется
    // `+` — то, что человек нажимает, а не то, как это называется внутри.
    registry.binding(KeyBinding('Shift-=', SelectByMaskCommand.commandId));
    registry.binding(KeyBinding('+', SelectByMaskCommand.commandId));
    registry.binding(KeyBinding('-', DeselectByMaskCommand.commandId));

    // Переход к имени по набранному символу. Стоит после привязок к конкретным
    // символам: иначе набор имени перехватывал бы их.
    registry.binding(
      const KeyBinding.anyCharacter(GoToNameCommand.commandId, characterParam: GoToNameCommand.characterParam),
    );
  }
}
