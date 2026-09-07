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
class Navigation implements FcFrontendModule {
  const Navigation();

  static const String commandId = 'fc.navigation';

  @override
  String get id => commandId;

  @override
  String get title => 'Navigation';

  @override
  void installFrontend(FrontendRegistry registry) {
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
    registry.command((context) => OpenInOtherPanelCommand());
    registry.command((context) => CenterSplitCommand());
    registry.command((context) => OpenNodeCommand());
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
    registry.command((context) => ToggleMarkInPlaceCommand());
    registry.command((context) => SelectAllCommand());
    registry.command((context) => SelectFilesCommand());
    registry.view<QuickSearchState>((context, state) => QuickSearchView(state: state));
    registry.command((context) => QuickSearchCommand());
    registry.command((context) => QuickSearchTypeCommand());
    registry.command((context) => QuickSearchEraseCommand());
    registry.command((context) => QuickSearchStopCommand());

    registry.settingsSchema(() {
      // Службы к этому времени уже есть: схему строят, когда окно открывают.
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.integer(
          'recentPathsLimit',
          defaultValue: NavigationSettings.defaultLimit,
          title: strings.tr('Address history'),
          unit: strings.tr('entries'),
          min: 0,
          max: 500,
          description: strings.tr('How many visited addresses the Address window remembers'),
          read: () => settingsOf().recentPathsLimit,
          write: (value) => settingsOf().recentPathsLimit = value,
        ),
      ], save: settings.save);
    });

    registry.strings('ru', _russian);

    _bindKeys(registry);
  }

  /// Клавиши. Порядок задаёт приоритет — он и есть содержание этого метода.
  void _bindKeys(FrontendRegistry registry) {
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
    // Привычка `mc`: показать соседке каталог под курсором, не сходя с места.
    registry.binding(KeyBinding('Alt-O', OpenInOtherPanelCommand.commandId));
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
    // Пробел — тоже буква имени, и в наборе он должен набираться, а не
    // помечать: «Program Files» иначе не наберёшь, а полоса пропадала на
    // середине слова. Клавишей отдельно, потому что печатным символом пробел
    // не считается: его имя длиннее одного знака.
    registry.binding(
      KeyBinding('Space', QuickSearchTypeCommand.commandId, parameters: {QuickSearchTypeCommand.characterParam: ' '}),
    );

    // Пометка объектов. Отмена операции идёт раньше сброса пометки.
    registry.binding(KeyBinding('Esc', CancelCommand.commandId));
    registry.binding(KeyBinding('Esc', ClearSelectionCommand.commandId));
    registry.binding(KeyBinding('Space', ToggleMarkCommand.commandId));
    // Пометка на месте: тот же пробел, но курсор остаётся на помеченном.
    registry.binding(KeyBinding('Shift-Space', ToggleMarkInPlaceCommand.commandId));
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

/// Русские строки навигации.
///
/// Ключ — английский текст, как он написан в коде: он же и запасное значение
/// (`docs/spec/localization.md`, §3).
const Map<String, String> _russian = {
  'Navigation': 'Навигация',

  // Курсор.
  'Cursor up': 'Курсор вверх',
  'Cursor down': 'Курсор вниз',
  'Page up': 'Страница вверх',
  'Page down': 'Страница вниз',
  'First item': 'В начало',
  'Last item': 'В конец',
  'Go to name': 'К имени',
  'Jump to the first item starting with the typed letter': 'Перейти к первому имени на набранную букву',

  // Панели и дерево.
  'Switch panel': 'Другая панель',
  'Open in the other panel': 'Открыть в соседней панели',
  'Show the directory under the cursor in the panel opposite': 'Показать каталог под курсором в соседней панели',
  'Make the other panel active': 'Сделать активной соседнюю панель',
  'Center split': 'Поровну',
  'Give both panels the same width': 'Дать панелям одинаковую ширину',
  'Open': 'Открыть',
  'Enter a directory or an archive': 'Войти в каталог или архив',
  'Open with system': 'Открыть системой',
  'Hand the selected items to the system, without entering them': 'Отдать выбранное системе, не входя внутрь',
  'Up': 'Наверх',
  'Leave for the parent directory': 'Выйти в родительский каталог',
  'Root': 'В корень',
  'Go to the root of the current source': 'Перейти в корень текущего источника',
  'Sizes': 'Размеры',
  'Measure every directory here, not just the marked ones': 'Посчитать размеры всех каталогов, а не только помеченных',
  'Reload': 'Перечитать',
  'Read the current directory again': 'Перечитать текущий каталог',
  'Hidden files': 'Скрытые файлы',
  'Show or hide the items whose names start with a dot': 'Показать или скрыть объекты, чьи имена начинаются с точки',
  'Show hidden files: On': 'Скрытые файлы: показаны',
  'Show hidden files: Off': 'Скрытые файлы: спрятаны',
  'panel|Cancel': 'Прервать',
  'Stop what the panel is doing right now': 'Остановить то, чем панель занята сейчас',

  // Пометка.
  'Mark': 'Пометить',
  'Mark in place': 'Пометить, не сходя с места',
  'Mark or unmark the item under the cursor, leaving the cursor on it':
      'Пометить объект под курсором или снять пометку, оставив курсор на нём',
  'Unmark': 'Снять пометку',
  'Mark or unmark the item under the cursor and step down': 'Пометить или снять пометку под курсором и шагнуть вниз',
  'Unmark all': 'Снять все пометки',
  'Drop the marks, leaving the cursor where it is': 'Снять пометки, оставив курсор на месте',
  'Mark files': 'Пометить файлы',
  'Mark files in the current directory, leaving directories alone':
      'Пометить файлы в текущем каталоге, не трогая каталоги',
  'Mark all': 'Пометить всё',
  'Mark everything in the current directory': 'Пометить всё в текущем каталоге',
  'Select by mask': 'Пометить по маске',
  'Mark everything matching a mask like «*.dart;*.md»': 'Пометить всё, что подходит под маску вроде «*.dart;*.md»',
  'Deselect by mask': 'Снять пометку по маске',
  'Unmark everything matching a mask like «*.dart;*.md»':
      'Снять пометку со всего, что подходит под маску вроде «*.dart;*.md»',
  'Mask': 'Маска',
  'No files selected': 'Ничего не выбрано',
  '{count} of {total}': '{count} из {total}',

  // Быстрый поиск.
  'Quick search': 'Быстрый поиск',
  'Move the cursor as you type the beginning of a name': 'Вести курсор за набранным началом имени',
  'Quick search: type': 'Быстрый поиск: буква',
  'Add a letter to what the quick search is looking for': 'Добавить букву к тому, что ищет быстрый поиск',
  'Quick search: erase': 'Быстрый поиск: стереть',
  'Remove the last letter from the quick search, or all of what did not match':
      'Убрать последнюю букву, а ненайденное — целиком',
  'Quick search: stop': 'Быстрый поиск: выйти',
  'Leave the quick search, keeping the cursor where it is': 'Выйти из быстрого поиска, оставив курсор на месте',
  'Search': 'Поиск',
  'Esc to leave': 'Esc — выйти',

  // Окно адреса.
  'Address': 'Адрес',
  'Open any path or address in the left or right panel': 'Открыть любой путь или адрес в левой или правой панели',
  'Open path (left panel)': 'Открыть путь (левая панель)',
  'Open path (right panel)': 'Открыть путь (правая панель)',
  'Path': 'Путь',
  'Status': 'Ход дела',
  'No matching address in history': 'В истории нет подходящего адреса',

  // Настройки.
  'Address history': 'История адресов',
  'How many visited addresses the Address window remembers': 'Сколько посещённых адресов помнит окно «Адрес»',
  'entries': 'записей',
};
