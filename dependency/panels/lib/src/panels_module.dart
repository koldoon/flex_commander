import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'brief_view.dart';
import 'brief_view_options.dart';
import 'file_table.dart';
import 'panels_settings.dart';
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

    // Таблица файлов — штатный вид содержимого панели. Остальные виды
    // (результаты поиска, дерево) объявляются так же, своими модулями.
    registry.viewport(PanelViewports.files, (context, panel) => FileTable(panel: panel));
    // Панель — тоже состояние области, и рисуется тем же механизмом, что всё
    // остальное: ядро не знает, чем показывают файлы.
    registry.view<Panel>((context, panel) => PanelView(panel: panel));

    // Таблица — вид по умолчанию, и объявляется она так же, как остальные:
    // отдельного «встроенного» вида нет, иначе виды делились бы на свои и
    // чужие (`docs/spec/panel-views.md`, §6).
    registry.panelView(
      PanelViewSpec(
        id: PanelSettings.defaultView,
        title: 'Table',
        description: 'Name, size, date — everything in columns',
        build: (context, panel) => FileTable(panel: panel),
      ),
    );

    registry.panelView(
      PanelViewSpec(
        id: BriefView.viewId,
        title: 'Brief',
        description: 'Names only, in columns',
        build: (context, panel) => BriefView(panel: panel, settings: settingsOf),
        options: (context) => BriefViewOptions(settings: settingsOf, save: settings.save),
      ),
    );

    registry.panelView(
      PanelViewSpec(
        id: TreeView.viewId,
        title: 'Tree',
        description: 'Everything as branches — where you are and what lies where',
        build: (context, panel) => TreeView(panel: panel, settings: settingsOf),
        options: (context) => TreeViewOptions(settings: settingsOf, save: settings.save),
      ),
    );

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
    registry.binding(
      KeyBinding('Cmd-2', SetPanelViewCommand.commandId, parameters: {SetPanelViewCommand.viewParam: BriefView.viewId}),
    );

    registry.binding(
      KeyBinding('Cmd-3', SetPanelViewCommand.commandId, parameters: {SetPanelViewCommand.viewParam: TreeView.viewId}),
    );

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
  'Name': 'Имя',
  'Path': 'Путь',
  'Ext': 'Расш',
  'Size': 'Размер',
  'Modified': 'Изменён',
  'Created': 'Создан',
  'Accessed': 'Открыт',
  'Attributes': 'Атрибуты',
  'Reset columns': 'Вернуть колонки',

  // Виды панели.
  'Table': 'Таблица',
  'Brief': 'Кратко',
  'Names only, in columns': 'Одни имена, столбцами',
  'brief|Columns': 'Столбцов',
  'As many as fit': 'Сколько влезет',
  'Tree': 'Дерево',
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
  'Show': 'Показать',

  // Строка состояния.
  '(Scanning…)': '(идёт подсчёт…)',
};

/// Множественные формы.
const Map<String, PluralForms> _plurals = {
  'Selected {n} items': (one: 'Выбран {n} объект', few: 'Выбрано {n} объекта', many: 'Выбрано {n} объектов'),
};
