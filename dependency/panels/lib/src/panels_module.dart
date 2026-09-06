import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'file_table.dart';
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
  'Name, size, date — everything in columns': 'Имя, размер, дата — всё колонками',
  'Panel view': 'Вид панели',
  'Show the directory another way': 'Показать каталог по-другому',
  'Panel view…': 'Вид панели…',
  'Choose how this panel shows the directory': 'Выбрать, чем эта панель показывает каталог',
  'Show': 'Показать',

  // Строка состояния.
  '(Scanning…)': '(идёт подсчёт…)',
};

/// Множественные формы.
const Map<String, PluralForms> _plurals = {
  'Selected {n} items': (one: 'Выбран {n} объект', few: 'Выбрано {n} объекта', many: 'Выбрано {n} объектов'),
};
