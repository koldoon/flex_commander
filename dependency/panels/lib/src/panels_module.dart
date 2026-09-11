import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'brief_view.dart';
import 'columns.dart';
import 'combined_view.dart';
import 'brief_view_options.dart';
import 'file_table.dart';
import 'panels_settings.dart';
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
class Panels implements FcBackendModule, FcFrontendModule {
  const Panels();

  @override
  String get id => 'fc.panels';

  @override
  String get title => 'File panels';

  /// Ядровая половина — одна: сравнения штатных колонок.
  ///
  /// Колонка расщеплена надвое общим идентификатором, и объявляется она по
  /// разу на каждой стороне: колбэк через границу не поедет
  /// (`docs/spec/column-registry.md`, §3.2).
  @override
  void installBackend(BackendRegistry registry) {
    installColumnSorting(registry);
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    installColumnCells(registry);

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
      ], save: settings.save);
    });

    // Таблица файлов — штатный вид содержимого панели. Остальные виды
    // (результаты поиска, дерево) объявляются так же, своими модулями.
    registry.viewport(PanelViewports.files, (context, panel) => FileTable(panel: panel, settings: settingsOf));
    // Панель — тоже состояние области, и рисуется тем же механизмом, что всё
    // остальное: ядро не знает, чем показывают файлы.
    registry.view<Session>((context, panel) => PanelView(panel: panel));

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
