import '../settings/app_settings.dart';
import '../settings/window_geometry.dart';
import 'entry_ref.dart';

/// Сессии одного набора и та из них, что показана.
///
/// Столбец у набора один, а у комбинированного вида два
/// (`docs/spec/panel-sessions.md`, §2).
class PanelLayout {
  const PanelLayout({required this.sessions, this.current = 0, this.name = ''});

  /// Личности сессий набора, в порядке столбцов.
  final List<PanelId> sessions;

  /// Номер показанного столбца.
  final int current;

  /// Имя, данное человеком; пусто — набор зовётся по каталогу.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is PanelLayout &&
      other.current == current &&
      other.name == name &&
      other.sessions.length == sessions.length &&
      // По одной: списки сравниваются ссылкой, а раскладка приезжает новой.
      List.generate(sessions.length, (i) => other.sessions[i] == sessions[i]).every((same) => same);

  @override
  int get hashCode => Object.hash(current, name, Object.hashAll(sessions));

  @override
  String toString() => 'PanelLayout($sessions, current: $current${name.isEmpty ? '' : ', "$name"'})';
}

/// Настройки, которые держит и правит экран.
///
/// Файл целиком принадлежит ядру — это ввод-вывод, — но вот это знает и меняет
/// экран: место окна, разделитель, активная панель, разделы модулей и размер
/// пула обхода (его правит окно настроек). Приезжает всё рукопожатием, а
/// правки уходят обратно сообщением; двух экземпляров, расходящихся между
/// собой, больше нет (`docs/spec/client-server.md`, §9).
class UiSettings {
  const UiSettings({
    this.activePanel = 0,
    this.splitRatio = 0.5,
    this.window,
    this.sizeScanConcurrency = AppSettings.defaultSizeScanConcurrency,
    this.reconnectAtStartup = false,
    this.modules = const {},
    this.panels = defaultPanels,
    this.shown = defaultShown,
  });

  /// Два набора по одной сессии — то, чем приложение и было до наборов.
  static const List<PanelLayout> defaultPanels = [
    PanelLayout(sessions: [PanelId.left]),
    PanelLayout(sessions: [PanelId.right]),
  ];

  /// Слева первый, справа второй.
  static const List<int> defaultShown = [0, 1];

  /// 0 — активна левая панель, 1 — правая.
  final int activePanel;

  /// Доля ширины окна под левой панелью.
  final double splitRatio;

  /// Положение и размер окна; null — окно ещё ни разу не открывали.
  final WindowGeometry? window;

  /// Сколько каталогов обходится за раз: настройка ядра, а правит её окно
  /// настроек — то есть эта сторона.
  final int sizeScanConcurrency;

  /// Подключаться ли при запуске к сохранённым удалённым источникам: настройка
  /// ядра, а правит её окно настроек — то есть эта сторона.
  final bool reconnectAtStartup;

  /// Разделы модулей — те же, что в файле, значениями.
  ///
  /// Целиком, а не «фронтовые»: раздел принадлежит **модулю**, а половин у
  /// модуля две, и читают они одно и то же. Незнакомое проезжает насквозь —
  /// отключённый модуль не должен терять свои настройки.
  final Map<String, dynamic> modules;

  /// Открытые наборы — одним списком на приложение.
  final List<PanelLayout> panels;

  /// Что показано слева и справа — номера наборов.
  final List<int> shown;

  UiSettings copyWith({
    int? activePanel,
    double? splitRatio,
    WindowGeometry? window,
    int? sizeScanConcurrency,
    bool? reconnectAtStartup,
    Map<String, dynamic>? modules,
    List<PanelLayout>? panels,
    List<int>? shown,
  }) => UiSettings(
    activePanel: activePanel ?? this.activePanel,
    splitRatio: splitRatio ?? this.splitRatio,
    window: window ?? this.window,
    sizeScanConcurrency: sizeScanConcurrency ?? this.sizeScanConcurrency,
    reconnectAtStartup: reconnectAtStartup ?? this.reconnectAtStartup,
    modules: modules ?? this.modules,
    panels: panels ?? this.panels,
    shown: shown ?? this.shown,
  );

  /// Разделы в сравнение не входят.
  ///
  /// Сравнением решается, нужна ли запись, а разделы модулей ради этого
  /// пришлось бы сличать деревом словарей на каждую правку. Свой признак у них
  /// есть и без того: раздел просит записать себя сам.
  @override
  bool operator ==(Object other) =>
      other is UiSettings &&
      other.activePanel == activePanel &&
      other.splitRatio == splitRatio &&
      other.window == window &&
      other.sizeScanConcurrency == sizeScanConcurrency &&
      other.reconnectAtStartup == reconnectAtStartup &&
      other.panels.length == panels.length &&
      List.generate(panels.length, (i) => other.panels[i] == panels[i]).every((same) => same) &&
      other.shown.length == shown.length &&
      List.generate(shown.length, (i) => other.shown[i] == shown[i]).every((same) => same);

  @override
  int get hashCode => Object.hash(
    activePanel,
    splitRatio,
    window,
    sizeScanConcurrency,
    reconnectAtStartup,
    Object.hashAll(panels),
    Object.hashAll(shown),
  );
}
