import '../serialization.dart';
import 'module_settings.dart';
import '../panel/column_spec.dart';
import '../panel/sort_spec.dart';
import 'window_geometry.dart';

/// Сохраняемые настройки одной панели.
///
/// Поля изменяемые: [fromMap] дописывает в готовый объект то, что нашлось
/// в файле, а чего в файле нет — остаётся как было. Поэтому «значение по
/// умолчанию» задаётся один раз, при создании, и не повторяется в разборе.
class PanelSettings implements Serializable {
  PanelSettings({
    this.path = '',
    this.cursor = '',
    this.cursorPath = '',
    this.scroll = 0,
    ColumnLayout? columns,
    this.sort = const SortSpec(),
    this.showHidden = false,
    this.view = defaultView,
    List<String>? expanded,
  }) : columns = columns ?? ColumnLayout.defaults,
       expanded = expanded ?? const [];

  /// Вид, которым панель показывает каталог, пока не выбрали другой.
  static const String defaultView = 'table';

  static PanelSettings defaults(String path) => PanelSettings(path: path);

  /// Последний открытый каталог: полная строка пути, включая схему провайдера.
  String path;

  /// Имя объекта под курсором в этом каталоге.
  ///
  /// Имя, а не номер строки: за время между запусками в каталоге прибавится
  /// или убавится файлов, и номер привёл бы курсор не туда. Пропавшее имя
  /// ставит курсор в начало — это честнее, чем угадывать соседа.
  String cursor;

  /// Путь строки под курсором — для видов, которым имени мало.
  ///
  /// В дереве видно много каталогов разом, и одинаковые имена в них — разные
  /// объекты: `src` есть и в `lib`, и в `test`. Имя остаётся ради списка
  /// (там оно честнее номера строки), а путь добавляется ради дерева
  /// (`docs/spec/panel-node-list.md`, §3).
  String cursorPath;

  /// Насколько список был промотан — в точках.
  ///
  /// Положение, а не настройка: сохраняется затем, чтобы при запуске экран
  /// выглядел так же, как при закрытии. Не подошло (данные снаружи изменились)
  /// — вид подматывает по своему правилу (`docs/spec/panel-view-tree.md`, §5).
  double scroll;

  ColumnLayout columns;
  SortSpec sort;
  bool showHidden;

  /// Чем панель показывает каталог: `table`, `brief`, `tree`…
  ///
  /// Строка, а не перечислимое: виды приносят модули, и ядру о них знать нечего
  /// — оно эту строку хранит и возвращает (`docs/spec/panel-views.md`, §7).
  /// Незнакомое имя не стирается: выключили модуль на один запуск — вид
  /// вернётся, когда его включат обратно.
  String view;

  /// Раскрытые ветви дерева — путями.
  ///
  /// Путями, а не узлами: между запусками узлов не остаётся вовсе, а путь
  /// переживает всё. Исчезнувшее при восстановлении пропускается молча
  /// (`docs/spec/panel-node-list.md`, §3).
  ///
  /// Хранится у панели, а не у вида: раскрытое — это состояние **набора
  /// строк**, и вернуться к нему панель должна независимо от того, каким видом
  /// его показывали.
  List<String> expanded;

  @override
  void toMap(Map<String, dynamic> m) {
    m['path'] = path;
    m['cursor'] = cursor;
    if (cursorPath.isNotEmpty) {
      m['cursorPath'] = cursorPath;
    }
    if (scroll > 0) {
      m['scroll'] = scroll;
    }
    m['showHidden'] = showHidden;
    m['view'] = view;
    // Раскладка колонок и правило сортировки — значения, а не документы:
    // `Serializable` устроен вокруг словаря, а колонки хранятся списком.
    m['sort'] = sort.toJson();
    m['columns'] = columns.toJson();
    if (expanded.isNotEmpty) {
      m['expanded'] = expanded;
    }
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    // Каталог, который подставили при создании: пустая строка в файле не должна
    // его затирать, иначе панель открылась бы в никуда.
    final fallback = path;
    path = extract(path, m['path']);
    if (path.isEmpty) {
      path = fallback;
    }

    cursor = extract(cursor, m['cursor']);
    cursorPath = extract(cursorPath, m['cursorPath']);
    scroll = extract(scroll, m['scroll']);
    showHidden = extract(showHidden, m['showHidden']);
    view = extract(view, m['view']);
    sort = SortSpec.fromJson(m['sort']);
    columns = ColumnLayout.fromJson(m['columns']);
    final saved = m['expanded'];
    expanded =
        saved is List
            ? [
              for (final path in saved)
                if (path is String) path,
            ]
            : const [];
  }
}

/// Сохраняемые настройки приложения.
/// Вкладка: то, что человек считает одной панелью.
///
/// Сессий в ней одна, а у комбинированного вида две — столбцы
/// (`docs/spec/panel-tabs.md`, §3). Пустой вкладки не бывает.
class PanelTabSettings implements Serializable {
  PanelTabSettings({List<PanelSettings>? panels, this.current = 0, this.pinned = false})
    : panels = panels == null || panels.isEmpty ? [PanelSettings()] : panels;

  final List<PanelSettings> panels;

  /// Номер показанного столбца.
  int current;

  /// Закреплённая: уход из неё открывает новую рядом.
  bool pinned;

  /// Показанный столбец; сбившийся номер приводит к первому, а не роняет
  /// разбор.
  PanelSettings get currentPanel => panels[current.clamp(0, panels.length - 1)];

  @override
  void toMap(Map<String, dynamic> m) {
    m['panels'] = [for (final panel in panels) serialize(panel)];
    m['current'] = current;
    if (pinned) {
      m['pinned'] = true;
    }
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    final stored = m['panels'];
    if (stored is List && stored.isNotEmpty) {
      panels
        ..clear()
        ..addAll(extractList<PanelSettings>(stored, (_) => PanelSettings()));
    }
    current = extract(current, m['current']).clamp(0, panels.length - 1);
    pinned = extract(pinned, m['pinned']);
  }
}

/// Вкладки одной стороны и та из них, что показана сейчас.
///
/// Сторон две, вкладок в стороне сколько завели (`docs/spec/panel-tabs.md`).
/// Пустым слот не бывает — сторона без панели это состояние, которого в модели
/// нет вовсе.
class PanelSlotSettings implements Serializable {
  PanelSlotSettings({List<PanelTabSettings>? tabs, List<PanelSettings>? panels, this.current = 0})
    : tabs = tabs == null || tabs.isEmpty ? [PanelTabSettings(panels: panels)] : tabs;

  final List<PanelTabSettings> tabs;

  /// Номер показанной вкладки.
  int current;

  /// Показанная вкладка.
  PanelTabSettings get currentTab => tabs[current.clamp(0, tabs.length - 1)];

  /// Показанная сессия показанной вкладки — то, чем панель была до вкладок.
  PanelSettings get currentPanel => currentTab.currentPanel;

  @override
  void toMap(Map<String, dynamic> m) {
    m['tabs'] = [for (final tab in tabs) serialize(tab)];
    m['current'] = current;
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    // Форм в файле три, и читаются все. Нынешняя — список вкладок; прежняя —
    // слот со списком сессий (одна вкладка); самая старая — голая панель
    // (`docs/spec/panel-tabs.md`, §4).
    final stored = m['tabs'];
    if (stored is List && stored.isNotEmpty) {
      tabs
        ..clear()
        ..addAll(extractList<PanelTabSettings>(stored, (_) => PanelTabSettings()));
    } else if (m['panels'] is List) {
      extract(tabs.first, m);
    }
    current = extract(current, m['current']).clamp(0, tabs.length - 1);
  }
}

class AppSettings implements Serializable {
  AppSettings({
    PanelSettings? left,
    PanelSettings? right,
    this.activePanel = 0,
    this.splitRatio = 0.5,
    this.sizeScanConcurrency = defaultSizeScanConcurrency,
    this.window,
    ModuleSettings? modules,
    List<PanelSlotSettings>? slots,
  }) : slots =
           slots ??
           [
             PanelSlotSettings(
               tabs: [
                 PanelTabSettings(panels: [left ?? PanelSettings()]),
               ],
             ),
             PanelSlotSettings(
               tabs: [
                 PanelTabSettings(panels: [right ?? PanelSettings()]),
               ],
             ),
           ],
       // Разделы модулей переносятся в новый снимок настроек как есть: это
       // живые объекты самих модулей, а не копия их значений.
       modules = modules ?? ModuleSettings();

  static AppSettings defaults(String path) =>
      AppSettings(left: PanelSettings.defaults(path), right: PanelSettings.defaults(path));

  /// Версия формата файла. Увеличивается, когда старый файл перестаёт
  /// читаться напрямую и нужен перенос настроек.
  static const int version = 1;

  /// Доля ширины окна под левой панелью.
  static const double minSplitRatio = 0.2;
  static const double maxSplitRatio = 0.8;

  /// Сколько каталогов панель обходит одновременно, считая их размер.
  ///
  /// Обход — работа не вычислительная, а ожидающая ответа файловой системы,
  /// поэтому несколько сразу заканчиваются заметно быстрее, чем по очереди.
  /// Предел нужен, чтобы не завалить диск сотней одновременных обходов, если
  /// помечены сотни каталогов.
  static const int defaultSizeScanConcurrency = 10;
  static const int minSizeScanConcurrency = 1;
  static const int maxSizeScanConcurrency = 64;

  /// Сессии каждой стороны; слотов ровно два — по числу сторон.
  ///
  /// Раскладку по сторонам держит экран, здесь она только хранится: ядро в неё
  /// не заглядывает (`docs/spec/panel-slots.md`, §5).
  final List<PanelSlotSettings> slots;

  /// Показанная сессия левой стороны — то, чем панель была до слотов.
  PanelSettings get left => slots[0].currentPanel;
  PanelSettings get right => slots[1].currentPanel;

  /// 0 — активна левая панель, 1 — правая.
  int activePanel;

  double splitRatio;

  /// Размер пула обхода каталогов, см. [defaultSizeScanConcurrency].
  int sizeScanConcurrency;

  /// Положение и размер окна; null — окно ещё ни разу не открывали.
  WindowGeometry? window;

  /// Настройки модулей: у каждого свой раздел под своим именем.
  ///
  /// Ядро в них не заглядывает — только хранит и отдаёт тому, кто спросит
  /// своё пространство имён.
  final ModuleSettings modules;

  @override
  void toMap(Map<String, dynamic> m) {
    m['version'] = version;
    m['activePanel'] = activePanel;
    m['splitRatio'] = splitRatio;
    m['sizeScanConcurrency'] = sizeScanConcurrency;
    if (window != null) {
      m['window'] = serialize(window);
    }
    m['panels'] = [for (final slot in slots) serialize(slot)];
    m['modules'] = serialize(modules);
  }

  /// Разбор устойчив к мусору: чего в файле нет или что в нём испорчено,
  /// остаётся умолчанием — этим занимаются [extract] и конверторы пакета.
  /// Полностью нечитаемый файл — забота `SettingsStore`.
  @override
  void fromMap(Map<String, dynamic> m) {
    activePanel = extract(activePanel, m['activePanel']) == 1 ? 1 : 0;
    splitRatio = extract(splitRatio, m['splitRatio']).clamp(minSplitRatio, maxSplitRatio);
    sizeScanConcurrency = extract(
      sizeScanConcurrency,
      m['sizeScanConcurrency'],
    ).clamp(minSizeScanConcurrency, maxSizeScanConcurrency);
    window = extractObject(m['window'], (_) => WindowGeometry());

    final moduleSections = m['modules'];
    if (moduleSections is Map<String, dynamic>) {
      modules.fromMap(moduleSections);
    }

    // Панели дописываются в уже готовые: в них лежит каталог по умолчанию,
    // и файл без пути его не потеряет.
    //
    // Форм в файле три, и все читаются: голая панель, слот со списком сессий и
    // слот со списком вкладок. Отличают их поля `tabs` и `panels`: у самой
    // панели ни того, ни другого нет и быть не может
    // (`docs/spec/panel-tabs.md`, §4).
    final stored = m['panels'];
    if (stored is List) {
      for (var i = 0; i < slots.length && i < stored.length; i++) {
        final item = stored[i];
        if (item is Map && (item['tabs'] is List || item['panels'] is List)) {
          extract(slots[i], item);
        } else {
          extract(slots[i].currentPanel, item);
        }
      }
    }
  }
}
