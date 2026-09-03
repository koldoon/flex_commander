import '../settings/app_settings.dart';
import '../settings/window_geometry.dart';

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
  });

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

  UiSettings copyWith({
    int? activePanel,
    double? splitRatio,
    WindowGeometry? window,
    int? sizeScanConcurrency,
    Map<String, dynamic>? modules,
  }) => UiSettings(
    activePanel: activePanel ?? this.activePanel,
    splitRatio: splitRatio ?? this.splitRatio,
    window: window ?? this.window,
    sizeScanConcurrency: sizeScanConcurrency ?? this.sizeScanConcurrency,
    modules: modules ?? this.modules,
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
      other.sizeScanConcurrency == sizeScanConcurrency;

  @override
  int get hashCode => Object.hash(activePanel, splitRatio, window, sizeScanConcurrency);
}
