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

/// Набор: то, что показывают как одно (`docs/spec/panel-sessions.md`, §2).
///
/// Сессия в нём одна, а у комбинированного вида две — столбцы. Пустым набор не
/// бывает.
class PanelGroupSettings implements Serializable {
  PanelGroupSettings({List<PanelSettings>? sessions, this.current = 0, this.name = ''})
    : sessions = sessions == null || sessions.isEmpty ? [PanelSettings()] : sessions;

  final List<PanelSettings> sessions;

  /// Номер показанной сессии — того столбца, в котором стоит курсор.
  int current;

  /// Имя, данное человеком; пусто — зовётся по каталогу
  /// (`docs/spec/panel-sessions.md`, §8).
  String name;

  /// Показанная сессия; сбившийся номер приводит к первой, а не роняет разбор.
  PanelSettings get currentSession => sessions[current.clamp(0, sessions.length - 1)];

  @override
  void toMap(Map<String, dynamic> m) {
    m['sessions'] = [for (final session in sessions) serialize(session)];
    m['current'] = current;
    if (name.isNotEmpty) {
      m['name'] = name;
    }
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    // Формы прежних лет читаются здесь же: `sessions` — нынешняя, `panels` —
    // та, что писали вкладки и слоты (`docs/spec/panel-sessions.md`, §10).
    final stored = m['sessions'] ?? m['panels'];
    if (stored is List && stored.isNotEmpty) {
      sessions
        ..clear()
        ..addAll(extractList<PanelSettings>(stored, (_) => PanelSettings()));
    } else {
      // Голая панель: набором она не назвалась, значит сама и есть сессия.
      sessions.first.fromMap(m);
    }
    current = extract(current, m['current']).clamp(0, sessions.length - 1);
    name = extract(name, m['name']);
  }
}

/// Сохраняемые настройки приложения: наборы, экран и разделы модулей.
class AppSettings implements Serializable {
  AppSettings({
    PanelSettings? left,
    PanelSettings? right,
    this.activePanel = 0,
    this.splitRatio = 0.5,
    this.sizeScanConcurrency = defaultSizeScanConcurrency,
    this.window,
    ModuleSettings? modules,
    List<PanelGroupSettings>? panels,
    List<int>? shown,
  }) : panels =
           panels ??
           [
             PanelGroupSettings(sessions: [left ?? PanelSettings()]),
             PanelGroupSettings(sessions: [right ?? PanelSettings()]),
           ],
       shown = shown ?? [0, 1],
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

  /// Открытые наборы — одним списком на приложение.
  ///
  /// Раскладку держит экран, здесь она только хранится: ядро в неё не
  /// заглядывает (`docs/spec/panel-sessions.md`, §10).
  final List<PanelGroupSettings> panels;

  /// Что показано слева и справа — номера наборов.
  ///
  /// Один и тот же набор в обеих сторонах — обычное дело и ничего не стоит.
  final List<int> shown;

  /// Набор, показанный с этой стороны; сбившийся номер приводит к первому.
  PanelGroupSettings groupAt(int side) =>
      panels[(side < shown.length ? shown[side] : side).clamp(0, panels.length - 1)];

  /// Показанная сессия левой стороны — то, чем панель была до наборов.
  PanelSettings get left => groupAt(0).currentSession;
  PanelSettings get right => groupAt(1).currentSession;

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
    m['panels'] = [for (final panel in panels) serialize(panel)];
    m['shown'] = shown;
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
    // Форм в файле четыре, и все читаются (`docs/spec/panel-sessions.md`, §10).
    // Нынешняя — список наборов; прежние — слот со списком вкладок, слот со
    // списком сессий и голая панель. Все прежние разворачиваются в наборы по
    // одной сессии, а стороны становятся первыми двумя номерами в [shown].
    final stored = m['panels'];
    if (stored is List && stored.isNotEmpty) {
      // Каталог по умолчанию — тот, с которым нас создали: сессия без пути в
      // файле должна открыться там же, где открылась бы без файла вовсе.
      final fallback = panels.first.sessions.first.path;
      final read = <PanelGroupSettings>[];
      final sides = <int>[];
      for (final item in stored) {
        if (item is! Map) {
          continue;
        }
        final tabs = item['tabs'];
        if (tabs is List && tabs.isNotEmpty) {
          // Слот со вкладками: каждая вкладка — набор, а показанная в слоте
          // становится показанной со своей стороны.
          sides.add(read.length + extract(0, item['current']).clamp(0, tabs.length - 1));
          for (final tab in tabs) {
            read.add(PanelGroupSettings()..fromMap(Map<String, dynamic>.from(tab as Map)));
          }
          continue;
        }
        sides.add(read.length);
        read.add(PanelGroupSettings()..fromMap(Map<String, dynamic>.from(item)));
      }
      if (read.isNotEmpty) {
        for (final group in read) {
          for (final session in group.sessions) {
            if (session.path.isEmpty) {
              session.path = fallback;
            }
          }
        }
        panels
          ..clear()
          ..addAll(read);
        final places = m['shown'];
        shown
          ..clear()
          ..addAll(
            places is List && places.length >= 2
                ? [for (final place in places.take(2)) extract(0, place).clamp(0, panels.length - 1)]
                : [
                  for (var side = 0; side < 2; side++)
                    side < sides.length ? sides[side].clamp(0, panels.length - 1) : 0,
                ],
          );
      }
    }
  }
}
