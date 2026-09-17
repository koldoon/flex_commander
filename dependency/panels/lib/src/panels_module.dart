import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'brief_view.dart';
import 'columns.dart';
import 'columns_commands.dart';
import 'columns_view.dart';
import 'combined_view.dart';
import 'crumbs_header.dart';
import 'brief_view_options.dart';
import 'file_table.dart';
import 'icons_view.dart';
import 'icons_view_options.dart';
import 'panels_settings.dart';
import 'table_view_options.dart';
import 'tree_view.dart';
import 'tree_view_options.dart';
import 'view_commands.dart';
import 'panel_view.dart';

/// Имя нынешнего заголовка — пути одной строкой.
///
/// Здесь, а не у виджета: набирает его `FcPathText` из общего набора, а
/// заголовком объявляет этот модуль (`docs/spec/panel-header.md`, §6).
const String pathHeaderId = 'path';

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
        options: (context, draft) => TableViewOptions(panel: draft.panel, draft: draft),
      ),
    );

    // Нынешняя плашка — тоже заголовок, объявленный модулем: иначе в окне
    // выбора её не из чего было бы выбрать, а «вернуть как было» — это тот же
    // выбор (`docs/spec/panel-header.md`, §6).
    registry.panelHeader(
      PanelHeaderSpec(
        id: pathHeaderId,
        title: 'Path',
        description: 'The whole address in one line',
        build: (context, view) => FcPathText(text: view.text, width: view.width, style: view.style),
      ),
    );

    registry.panelHeader(
      PanelHeaderSpec(
        id: crumbsHeaderId,
        title: 'Crumbs',
        description: 'Address by links: press one to go there',
        build: (context, view) => CrumbsHeader(view: view),
      ),
    );

    registry.panelView(
      PanelViewSpec(
        id: BriefView.viewId,
        title: 'Brief',
        description: 'Names only, in columns',
        build: (context, panel) => BriefView(panel: panel, settings: settingsOf),
        options: (context, draft) => BriefViewOptions(settings: settingsOf, save: settings.save, draft: draft),
      ),
    );

    registry.panelView(
      PanelViewSpec(
        id: TreeView.viewId,
        title: 'Tree',
        description: 'Everything as branches — where you are and what lies where',
        build: (context, panel) => TreeView(panel: panel, settings: settingsOf),
        options: (context, draft) => TreeViewOptions(settings: settingsOf, save: settings.save, draft: draft),
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
        options: (context, draft) => TableViewOptions(panel: CombinedView.listOf(context, draft.panel), draft: draft),
      ),
    );

    // Последним, а не по соседству с кратким: порядок списка видов — это
    // порядок их быстрых клавиш, и сетка получает `Cmd-5`.
    registry.panelView(
      PanelViewSpec(
        id: IconsView.viewId,
        // Листается целиком, как картинка в просмотрщике: плитки уезжают под
        // плашку пути, а не упираются в полосу фона под ней.
        fillsFrame: true,
        title: 'Icons',
        description: 'A grid of tiles: a picture and a name under it',
        build: (context, panel) => IconsView(panel: panel, settings: settingsOf),
        options: (context, draft) => IconsViewOptions(settings: settingsOf, save: settings.save, draft: draft),
      ),
    );

    // Столбцы объявляются после сетки и получают `Cmd-6` — последнюю из
    // отведённого ряда. Настраивать в окне выбора нечего: ширину столбца правят
    // прямой манипуляцией, а два места для одного числа расходятся
    // (`docs/spec/panel-views.md`, §7).
    registry.panelView(
      PanelViewSpec(
        id: ColumnsView.viewId,
        // «Path columns», а не «Columns»: одно слово уже занято колонками
        // таблицы — и в справке, и в окне раскладки. Английский текст здесь
        // ключ перевода, и два разных места с одним ключом получили бы один
        // перевод на двоих.
        title: 'Path columns',
        description: 'The path as a chain of directories, left to right',
        build: (context, panel) => ColumnsView(panel: panel, settings: settingsOf, save: settings.save),
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

    registry.binding(
      KeyBinding('Cmd-5', SetPanelViewCommand.commandId, parameters: {SetPanelViewCommand.viewParam: IconsView.viewId}),
    );

    registry.binding(
      KeyBinding(
        'Cmd-6',
        SetPanelViewCommand.commandId,
        parameters: {SetPanelViewCommand.viewParam: ColumnsView.viewId},
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

    // Столбцы — раньше дерева и позже комбинированного вида: строки здесь
    // древесные, и раскрытие ветви забрало бы обе стрелки себе, а `Home` увёл
    // бы курсор на корень, которого в столбцах не видно
    // (`docs/spec/panel-view-columns.md`, §6).
    registry.command((context) => ColumnsStepCommand(deeper: true));
    registry.command((context) => ColumnsStepCommand(deeper: false));
    for (final step in ColumnsRowStep.values) {
      for (final down in const [false, true]) {
        registry.command((context) => ColumnsRowCommand(down: down, step: step));
      }
    }
    registry.command((context) => ColumnsMarkCommand());
    // Раньше общей пометки: у той шаг вниз — «следующая строка списка», а в
    // столбцах это содержимое раскрытого каталога.
    registry.binding(KeyBinding('Space', ColumnsMarkCommand.commandId));
    registry.binding(KeyBinding('Right', ColumnsStepCommand.inId));
    registry.binding(KeyBinding('Left', ColumnsStepCommand.outId));
    registry.binding(KeyBinding('Up', ColumnsRowCommand.upId));
    registry.binding(KeyBinding('Down', ColumnsRowCommand.downId));
    registry.binding(KeyBinding('PgUp', ColumnsRowCommand.pageUpId));
    registry.binding(KeyBinding('PgDn', ColumnsRowCommand.pageDownId));
    registry.binding(KeyBinding('Home', ColumnsRowCommand.firstId));
    registry.binding(KeyBinding('End', ColumnsRowCommand.lastId));

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

    // Ряды — там, где они есть: в сетке значков. В прочих видах команда
    // невыполнима, и `Up`/`Down` достаются навигации, как доставались всегда.
    registry.command((context) => MoveCursorRowCommand(down: false));
    registry.command((context) => MoveCursorRowCommand(down: true));
    registry.binding(KeyBinding('Up', MoveCursorRowCommand.upId));
    registry.binding(KeyBinding('Down', MoveCursorRowCommand.downId));
  }
}

/// Русские строки файловых панелей.
///
/// Названия колонок приходят значениями (`FsColumn.title`), а не литералами в
/// вызове: переводит их тот, кто показывает, — но объявлены они здесь, у того,
/// кто эти колонки рисует.
const Map<String, String> _russian = {
  'Row above': 'Ряд выше',
  'Row below': 'Ряд ниже',
  'Move the cursor one row of tiles': 'Перевести курсор на ряд плиток',
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
  'Owner': 'Владелец',
  'Group': 'Группа',

  // Форматы вывода колонок.
  'Auto': 'Авто',
  'Bytes': 'Байты',
  'KB, MB, GB': 'КБ, МБ, ГБ',
  'kB, MB, GB': 'кБ, МБ, ГБ',
  // «Name» уже переведён выше — колонка имени и формат владельца зовутся
  // одинаково, и перевод у них один.
  'Number': 'Число',
  'Columns visible': 'Видимые колонки',
  // «Path» уже переведён выше — колонка и заголовок зовутся одинаково, и
  // перевод у них один.
  'The whole address in one line': 'Весь адрес одной строкой',
  'Crumbs': 'Звенья',
  'Address by links: press one to go there': 'Адрес звеньями: нажатие уводит туда',

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
  'Icons': 'Значки',
  'A grid of tiles: a picture and a name under it': 'Сетка плиток: картинка и имя под ней',
  'Icon size': 'Размер значка',
  'Name width': 'Ширина имени',
  'Custom': 'Своё',
  'Path columns': 'Столбцы',
  'Into the directory': 'В каталог',
  'Out to the parent': 'К родителю',
  'Show what is inside and move the cursor there': 'Показать содержимое и перевести туда курсор',
  'Move the cursor to the directory this column grew from': 'Перевести курсор на каталог, из которого вырос столбец',
  'Row above in the column': 'Строка выше в столбце',
  'Row below in the column': 'Строка ниже в столбце',
  'Column page up': 'Столбец страницей вверх',
  'Column page down': 'Столбец страницей вниз',
  'First row of the column': 'Первая строка столбца',
  'Last row of the column': 'Последняя строка столбца',
  'Move the cursor inside its own column': 'Двигать курсор внутри своего столбца',
  'Mark or unmark the item under the cursor and step down the column':
      'Пометить объект под курсором или снять пометку и шагнуть вниз по столбцу',
  'The path as a chain of directories, left to right': 'Путь цепочкой каталогов, слева направо',
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
