import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'brief_view.dart';
import 'combined_view.dart';
import 'brief_view_options.dart';
import 'file_table.dart';
import 'panels_settings.dart';
import 'tab_commands.dart';
import 'table_view_options.dart';
import 'tree_view.dart';
import 'tree_view_options.dart';
import 'view_commands.dart';
import 'panel_view.dart';

/// Файловые панели.
///
/// Ядро не знает, чем показывают файлы: оно показывает верхний экран стопки и
/// рисует ряд функциональных кнопок. Этот модуль приносит и сам экран, и
/// таблицу файлов как штатный вид содержимого панели.
///
/// Без него приложение соберётся и запустится — просто выше ряда кнопок будет
/// пусто. Так же честно, как сейчас без корневого провайдера.
class Panels implements FcFrontendModule {
  const Panels();

  @override
  String get id => 'fc.panels';

  @override
  String get title => 'File panels';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    // Область забирается **сейчас**, пока идёт установка: позже имя раздела уже
    // неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    PanelsSettings settingsOf() => settings.section(PanelsSettings.new);

    // Раздел в окне настроек: одно правило, общее на все виды панели. Прочее,
    // что живёт в `PanelsSettings`, — выбор вида, и спрашивают его там же, в
    // окне выбора (`Alt-F1`).
    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'cursorHoldsPlace',
          defaultValue: true,
          title: strings.tr('Sorting keeps the cursor row in place'),
          description: strings.tr('The list is reordered and the view moves with the row, so nothing jumps'),
          read: () => settingsOf().cursorHoldsPlace,
          write: (value) => settingsOf().cursorHoldsPlace = value,
        ),
        SettingsField.flag(
          'tabsAlwaysVisible',
          defaultValue: false,
          title: strings.tr('Always show the tab row'),
          description: strings.tr('Otherwise it appears with the second tab: an empty row eats a line of the list'),
          read: () => settingsOf().tabsAlwaysVisible,
          write: (value) => settingsOf().tabsAlwaysVisible = value,
        ),
        SettingsField.integer(
          'maxTabs',
          min: PanelsSettings.minTabs,
          max: PanelsSettings.maxTabsLimit,
          defaultValue: PanelsSettings.defaultMaxTabs,
          title: strings.tr('Tabs per side'),
          description: strings.tr('A tab holds its source open: five archives are five unpacked copies'),
          read: () => settingsOf().maxTabs,
          write: (value) => settingsOf().maxTabs = value,
        ),
      ], save: settings.save);
    });

    // Таблица файлов — штатный вид содержимого панели. Остальные виды
    // (результаты поиска, дерево) объявляются так же, своими модулями.
    registry.viewport(PanelViewports.files, (context, panel) => FileTable(panel: panel, settings: settingsOf));
    // Панель — тоже состояние области, и рисуется тем же механизмом, что всё
    // остальное: ядро не знает, чем показывают файлы.
    registry.view<Panel>((context, panel) => PanelView(panel: panel, settings: settingsOf));

    // Таблица — вид по умолчанию, и объявляется она так же, как остальные:
    // отдельного «встроенного» вида нет, иначе виды делились бы на свои и
    // чужие (`docs/spec/panel-views.md`, §6).
    registry.panelView(
      PanelViewSpec(
        id: PanelSettings.defaultView,
        title: 'Table',
        description: 'Name, size, date — everything in columns',
        build: (context, panel) => FileTable(panel: panel, settings: settingsOf),
        // Колонки — панельные: у левой и правой они свои, и правит их та
        // панель, для которой окно открыли.
        options: (context, panel) => TableViewOptions(panel: panel),
      ),
    );

    registry.panelView(
      PanelViewSpec(
        id: BriefView.viewId,
        title: 'Brief',
        description: 'Names only, in columns',
        build: (context, panel) => BriefView(panel: panel, settings: settingsOf),
        options: (context, panel) => BriefViewOptions(settings: settingsOf, save: settings.save),
      ),
    );

    registry.panelView(
      PanelViewSpec(
        id: TreeView.viewId,
        title: 'Tree',
        description: 'Everything as branches — where you are and what lies where',
        build: (context, panel) => TreeView(panel: panel, settings: settingsOf),
        options: (context, panel) => TreeViewOptions(settings: settingsOf, save: settings.save),
      ),
    );

    registry.panelView(
      PanelViewSpec(
        id: CombinedView.viewId,
        title: 'Tree with contents',
        description: 'Branches on the left, what is inside on the right',
        build: (context, panel) => CombinedView(panel: panel, settings: settingsOf, save: settings.save),
        // Настройки — списка: колонки настраиваются у него, а дереву одних
        // каталогов настраивать нечего — там имя и ничего больше
        // (`docs/spec/panel-view-combined.md`, §7).
        options: (context, panel) => TableViewOptions(panel: CombinedView.listOf(context, panel)),
      ),
    );

    // Четыре команды дерева: поддерево под курсором и всё дерево, каждое — в
    // обе стороны (`docs/spec/panel-view-tree.md`, §6а).
    for (final expand in const [true, false]) {
      for (final all in const [true, false]) {
        registry.command((context) => TreeDeepCommand(expand: expand, all: all));
      }
    }

    registry.command((context) => TreeFollowLinkCommand());

    // Вкладки: ряд рисует этот же модуль, и команды его же
    // (`docs/spec/panel-tabs.md`).
    registry.command((context) => NewTabCommand(settings: settingsOf));
    registry.command((context) => CloseTabCommand());
    registry.command((context) => CycleTabsCommand(forward: true));
    registry.command((context) => CycleTabsCommand(forward: false));
    registry.command((context) => SelectTabCommand());
    registry.command((context) => ToggleTabLockCommand());
    registry.binding(KeyBinding('Cmd-Shift-T', NewTabCommand.commandId));
    registry.binding(KeyBinding('Cmd-Shift-W', CloseTabCommand.commandId));
    // `Ctrl-Tab` — тот, к которому все привыкли: `Ctrl` и `Cmd` у нас разные
    // модификаторы, на macOS это сочетание свободно, а на Windows и Linux оно
    // и есть родное.
    registry.binding(KeyBinding('Ctrl-Tab', CycleTabsCommand.nextId));
    registry.binding(KeyBinding('Ctrl-Shift-Tab', CycleTabsCommand.previousId));
    for (var number = 1; number <= 9; number++) {
      registry.binding(
        KeyBinding('Alt-$number', SelectTabCommand.commandId, parameters: {SelectTabCommand.numberParam: '$number'}),
      );
    }

    registry.command((context) => SetPanelViewCommand());
    registry.command((context) => ChoosePanelViewCommand());

    // Выбор вида — для той панели, которую назвали: слева и справа он свой.
    // Привычка `mc`, где этими же клавишами меняют диск.
    registry.binding(
      KeyBinding(
        'Alt-F1',
        ChoosePanelViewCommand.commandId,
        parameters: {SetPanelViewCommand.panelParam: SetPanelViewCommand.leftPanel},
      ),
    );
    registry.binding(
      KeyBinding(
        'Alt-F2',
        ChoosePanelViewCommand.commandId,
        parameters: {SetPanelViewCommand.panelParam: SetPanelViewCommand.rightPanel},
      ),
    );
    // Быстрая клавиша своего вида: каждый вид привязывает её сам, и таблица —
    // не исключение.
    registry.binding(
      KeyBinding(
        'Cmd-1',
        SetPanelViewCommand.commandId,
        parameters: {SetPanelViewCommand.viewParam: PanelSettings.defaultView},
      ),
    );

    // Раскрытие вглубь: `Shift` к тем же стрелкам, что раскрывают ветвь на шаг,
    // а `Cmd` к ним — всё дерево. Клавиши свободны, а смысл читается сам:
    // «то же, но целиком» (`docs/spec/panel-view-tree.md`, §6а).
    registry.binding(KeyBinding('Shift-Right', TreeDeepCommand.expandSubtreeId));
    registry.binding(KeyBinding('Shift-Left', TreeDeepCommand.collapseSubtreeId));
    registry.binding(KeyBinding('Shift-Cmd-Right', TreeDeepCommand.expandAllId));
    registry.binding(KeyBinding('Shift-Cmd-Left', TreeDeepCommand.collapseAllId));
    registry.binding(
      KeyBinding('Cmd-2', SetPanelViewCommand.commandId, parameters: {SetPanelViewCommand.viewParam: BriefView.viewId}),
    );

    registry.binding(
      KeyBinding('Cmd-3', SetPanelViewCommand.commandId, parameters: {SetPanelViewCommand.viewParam: TreeView.viewId}),
    );

    registry.binding(
      KeyBinding(
        'Cmd-4',
        SetPanelViewCommand.commandId,
        parameters: {SetPanelViewCommand.viewParam: CombinedView.viewId},
      ),
    );

    // Столбцы комбинированного вида — раньше всего прочего, что висит на этих
    // стрелках: раскрытие ветви объявлено следом и потому получает `Right`
    // ровно там, где переход невыполним, — на закрытой ветви
    // (`docs/spec/panel-view-combined.md`, §6).
    registry.command((context) => CombinedSideCommand(toList: true));
    registry.command((context) => CombinedSideCommand(toList: false));
    registry.binding(KeyBinding('Right', CombinedSideCommand.toListId));
    registry.binding(KeyBinding('Left', CombinedSideCommand.toTreeId));

    // Курсор и пометка в дереве — **панельные**: строки собирает ядро, и
    // ходить по ним нечем иным (`docs/spec/panel-node-list.md`, §3). Своими
    // остались только раскрытие и сворачивание: смысл у `Left` и `Right` тут
    // другой.
    //
    // Порядок привязок и есть выбор команды: дерево раньше столбцов, столбцы
    // раньше «в начало» и «в конец». Где дерева нет — команда невыполнима, и
    // клавиша идёт дальше (`docs/spec/panel-views.md`, §10).
    registry.command((context) => TreeBranchCommand(expand: false));
    registry.command((context) => TreeBranchCommand(expand: true));
    registry.command((context) => ToggleTreeBranchCommand());
    registry.binding(KeyBinding('Left', TreeBranchCommand.collapseId));
    registry.binding(KeyBinding('Right', TreeBranchCommand.expandId));
    // Ссылка раньше ветви: над ссылкой `Enter` значит «сходить к цели», и
    // выигрывает та привязка, что объявлена раньше.
    registry.binding(KeyBinding('Enter', TreeFollowLinkCommand.commandId));
    registry.binding(KeyBinding('Enter', ToggleTreeBranchCommand.commandId));

    registry.command((context) => MoveCursorColumnCommand(right: false));
    registry.command((context) => MoveCursorColumnCommand(right: true));
    registry.binding(KeyBinding('Left', MoveCursorColumnCommand.leftId));
    registry.binding(KeyBinding('Right', MoveCursorColumnCommand.rightId));
  }
}

/// Русские строки файловых панелей.
///
/// Названия колонок приходят значениями (`FsColumn.title`), а не литералами в
/// вызове: переводит их тот, кто показывает, — но объявлены они здесь, у того,
/// кто эти колонки рисует.
const Map<String, String> _russian = {
  'File panels': 'Файловые панели',

  // Заголовки колонок.
  // У колонки значка заголовка нет; имя ей нужно только в списке колонок.
  'Icon': 'Значок',
  'Name': 'Имя',
  'Path': 'Путь',
  'Ext': 'Расш',
  'Size': 'Размер',
  'Modified': 'Изменён',
  'Created': 'Создан',
  'Accessed': 'Открыт',
  'Attributes': 'Атрибуты',
  'Columns visible': 'Видимые колонки',

  // Вкладки.
  'New tab': 'Новая вкладка',
  'Open one more tab on the current directory': 'Завести ещё одну вкладку на текущем каталоге',
  'Close tab': 'Закрыть вкладку',
  'Close this tab and let its source go': 'Закрыть вкладку и отпустить её источник',
  'Next tab': 'Следующая вкладка',
  'Previous tab': 'Предыдущая вкладка',
  'Switch to the neighbouring tab': 'Перейти к соседней вкладке',
  'Tab by number': 'Вкладка по номеру',
  'Show the tab with this number': 'Показать вкладку с этим номером',
  'Pin tab': 'Закрепить вкладку',
  'Always show the tab row': 'Всегда показывать ряд вкладок',
  'Otherwise it appears with the second tab: an empty row eats a line of the list':
      'Иначе он появляется со второй вкладкой: пустой ряд отнимает строку у списка',
  'Tabs per side': 'Вкладок на сторону',
  'A tab holds its source open: five archives are five unpacked copies':
      'Вкладка держит свой источник открытым: пять архивов — пять распакованных копий',
  'A pinned tab stays on its directory; leaving it opens a new one':
      'Закреплённая вкладка остаётся на своём каталоге, а уход из неё открывает новую',

  // Комбинированный вид.
  'Tree with contents': 'Дерево с содержимым',
  'Branches on the left, what is inside on the right': 'Ветви слева, содержимое — справа',
  'To the list': 'В список',
  'To the tree': 'В дерево',
  'Move the cursor to the other column': 'Перевести курсор в соседний столбец',

  // Настройки панелей.
  'Sorting keeps the cursor row in place': 'Сортировка не двигает строку под курсором',
  'The list is reordered and the view moves with the row, so nothing jumps':
      'Список переставляется, а вид едет вместе со строкой — ничего не прыгает',

  // Виды панели.
  'Table': 'Таблица',
  'Brief': 'Кратко',
  'Names only, in columns': 'Одни имена, столбцами',
  'brief|Columns': 'Столбцов',
  'As many as fit': 'Сколько влезет',
  'Tree': 'Дерево',
  'Expand all': 'Раскрыть всё',
  'Expand subtree': 'Раскрыть поддерево',
  'Collapse all': 'Свернуть всё',
  'Collapse subtree': 'Свернуть поддерево',
  'Open every branch of the tree — up to a limit': 'Раскрыть все ветви дерева — до предела',
  'Open the branch under the cursor and everything inside it': 'Раскрыть ветвь под курсором и всё, что в ней',
  'Close every branch, leaving the roots': 'Свернуть все ветви, оставив корни',
  'Close the branch under the cursor and everything inside it': 'Свернуть ветвь под курсором и всё, что в ней',
  'Expanded {count} branches — the rest by hand': 'Раскрыто {count} ветвей — дальше вручную',
  'Go to link target': 'Перейти к цели ссылки',
  'Move the cursor to what the link points at': 'Поставить курсор на то, куда ведёт ссылка',
  'The link leads nowhere: {name}': 'Ссылка ведёт в никуда: {name}',
  'Everything as branches — where you are and what lies where': 'Всё ветвями — где вы сейчас и что где лежит',
  'Branch up': 'Ветвь выше',
  'Branch down': 'Ветвь ниже',
  'Branches page up': 'Ветви страницей вверх',
  'Branches page down': 'Ветви страницей вниз',
  'First branch': 'Первая ветвь',
  'Last branch': 'Последняя ветвь',
  'Expand branch': 'Раскрыть ветвь',
  'Collapse branch': 'Свернуть ветвь',
  'Expand the branch under the cursor': 'Раскрыть ветвь под курсором',
  'Collapse the branch, or step out to the directory it lies in':
      'Свернуть ветвь, а сворачивать нечего — перевести курсор в каталог, где она лежит',
  'Toggle branch': 'Раскрыть или свернуть',
  'Expand the branch, or collapse it back': 'Раскрыть ветвь или свернуть обратно',
  'tree|Columns': 'Колонки',
  'Modified (not implemented)': 'Дата (ещё не сделана)',
  'Mark branch': 'Пометить ветвь',
  'Mark or unmark the branch under the cursor and step down':
      'Пометить или снять пометку с ветви под курсором и шагнуть вниз',
  'Column left': 'Столбец левее',
  'Column right': 'Столбец правее',
  'Move the cursor one column aside': 'Перевести курсор на столбец вбок',
  'Name, size, date — everything in columns': 'Имя, размер, дата — всё колонками',
  'Set panel view': 'Задать вид панели',
  'Show the directory another way': 'Показать каталог по-другому',
  'Panel view': 'Вид панели',
  'Choose how this panel shows the directory': 'Выбрать, чем эта панель показывает каталог',
  'OK': 'ОК',

  // Строка состояния.
  '(Scanning…)': '(идёт подсчёт…)',
};

/// Множественные формы.
const Map<String, PluralForms> _plurals = {
  'Selected {n} items': (one: 'Выбран {n} объект', few: 'Выбрано {n} объекта', many: 'Выбрано {n} объектов'),
};
