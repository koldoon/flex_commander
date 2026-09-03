import '../settings/window_geometry.dart';

/// Настройки, принадлежащие экрану.
///
/// Файл настроек целиком принадлежит ядру — это ввод-вывод, — но вот эти три
/// вещи знает только экран: какое у окна место на рабочем столе, где стоит
/// разделитель панелей и в какой из них сейчас работают. Приезжают они
/// рукопожатием, а правки уходят обратно сообщением; двух экземпляров,
/// расходящихся между собой, больше нет
/// (`docs/spec/client-server.md`, §9).
class UiSettings {
  const UiSettings({this.activePanel = 0, this.splitRatio = 0.5, this.window});

  /// 0 — активна левая панель, 1 — правая.
  final int activePanel;

  /// Доля ширины окна под левой панелью.
  final double splitRatio;

  /// Положение и размер окна; null — окно ещё ни разу не открывали.
  final WindowGeometry? window;

  UiSettings copyWith({int? activePanel, double? splitRatio, WindowGeometry? window}) => UiSettings(
    activePanel: activePanel ?? this.activePanel,
    splitRatio: splitRatio ?? this.splitRatio,
    window: window ?? this.window,
  );

  @override
  bool operator ==(Object other) =>
      other is UiSettings &&
      other.activePanel == activePanel &&
      other.splitRatio == splitRatio &&
      other.window == window;

  @override
  int get hashCode => Object.hash(activePanel, splitRatio, window);
}
