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
  PanelSettings({this.path = '', ColumnLayout? columns, this.sort = const SortSpec(), this.showHidden = false})
    : columns = columns ?? ColumnLayout.defaults;

  static PanelSettings defaults(String path) => PanelSettings(path: path);

  /// Последний открытый каталог: полная строка пути, включая схему провайдера.
  String path;

  ColumnLayout columns;
  SortSpec sort;
  bool showHidden;

  @override
  void toMap(Map<String, dynamic> m) {
    m['path'] = path;
    m['showHidden'] = showHidden;
    // Раскладка колонок и правило сортировки — значения, а не документы:
    // `Serializable` устроен вокруг словаря, а колонки хранятся списком.
    m['sort'] = sort.toJson();
    m['columns'] = columns.toJson();
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

    showHidden = extract(showHidden, m['showHidden']);
    sort = SortSpec.fromJson(m['sort']);
    columns = ColumnLayout.fromJson(m['columns']);
  }
}

/// Сохраняемые настройки приложения.
class AppSettings implements Serializable {
  AppSettings({
    PanelSettings? left,
    PanelSettings? right,
    this.activePanel = 0,
    this.splitRatio = 0.5,
    this.sizeScanConcurrency = defaultSizeScanConcurrency,
    this.window,
    ModuleSettings? modules,
  }) : left = left ?? PanelSettings(),
       right = right ?? PanelSettings(),
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

  PanelSettings left;
  PanelSettings right;

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
    m['panels'] = [serialize(left), serialize(right)];
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
    final panels = m['panels'];
    if (panels is List) {
      if (panels.isNotEmpty) {
        extract(left, panels[0]);
      }
      if (panels.length > 1) {
        extract(right, panels[1]);
      }
    }
  }
}
