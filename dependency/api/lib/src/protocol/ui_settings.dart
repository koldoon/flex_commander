import '../settings/app_settings.dart';
import '../settings/window_geometry.dart';
import 'entry_ref.dart';

/// Какие сессии стоят в стороне и которая из них показана.
///
/// Раскладка — дело экрана: ядро знает сессии, но не знает, где они
/// (`docs/spec/panel-slots.md`, §2). В настройки она попадает через него же,
/// как и всё прочее экранное.
class SlotLayout {
  const SlotLayout({required this.panels, this.current = 0});

  /// Личности сессий стороны, в том порядке, в каком они показаны.
  final List<PanelId> panels;

  /// Номер показанной.
  final int current;

  @override
  bool operator ==(Object other) =>
      other is SlotLayout &&
      other.current == current &&
      other.panels.length == panels.length &&
      // По одной: списки сравниваются ссылкой, а раскладка приезжает новой.
      List.generate(panels.length, (i) => other.panels[i] == panels[i]).every((same) => same);

  @override
  int get hashCode => Object.hash(current, Object.hashAll(panels));

  @override
  String toString() => 'SlotLayout($panels, current: $current)';
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
    this.modules = const {},
    this.slots = defaultSlots,
  });

  /// По одной сессии на сторону — то, чем приложение и было до слотов.
  static const List<SlotLayout> defaultSlots = [
    SlotLayout(panels: [PanelId.left]),
    SlotLayout(panels: [PanelId.right]),
  ];

  /// 0 — активна левая панель, 1 — правая.
  final int activePanel;

  /// Доля ширины окна под левой панелью.
  final double splitRatio;

  /// Положение и размер окна; null — окно ещё ни разу не открывали.
  final WindowGeometry? window;

  /// Сколько каталогов обходится за раз: настройка ядра, а правит её окно
  /// настроек — то есть эта сторона.
  final int sizeScanConcurrency;

  /// Разделы модулей — те же, что в файле, значениями.
  ///
  /// Целиком, а не «фронтовые»: раздел принадлежит **модулю**, а половин у
  /// модуля две, и читают они одно и то же. Незнакомое проезжает насквозь —
  /// отключённый модуль не должен терять свои настройки.
  final Map<String, dynamic> modules;

  /// Сессии по сторонам: слот на сторону, в слоте — сколько их там сейчас.
  final List<SlotLayout> slots;

  UiSettings copyWith({
    int? activePanel,
    double? splitRatio,
    WindowGeometry? window,
    int? sizeScanConcurrency,
    Map<String, dynamic>? modules,
    List<SlotLayout>? slots,
  }) => UiSettings(
    activePanel: activePanel ?? this.activePanel,
    splitRatio: splitRatio ?? this.splitRatio,
    window: window ?? this.window,
    sizeScanConcurrency: sizeScanConcurrency ?? this.sizeScanConcurrency,
    modules: modules ?? this.modules,
    slots: slots ?? this.slots,
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
      other.slots.length == slots.length &&
      List.generate(slots.length, (i) => other.slots[i] == slots[i]).every((same) => same);

  @override
  int get hashCode => Object.hash(activePanel, splitRatio, window, sizeScanConcurrency, Object.hashAll(slots));
}
