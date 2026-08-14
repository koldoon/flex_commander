/// Размеры интерфейса.
///
/// Значения сняты с макета `docs/design/design.svg` (он нарисован в масштабе 1:1,
/// поэтому это логические пиксели). Геометрия панели там такая:
///
///     0…10     верхняя половина «плашки» пути — над рамкой панели
///     10       рамка панели
///     10…33    отступ до заголовков (в нём лежит нижняя половина плашки)
///     33…59    строка заголовков колонок
///     60…      строки файлов по 20 px
///     …559     строка состояния высотой 30 px
class FcMetrics {
  const FcMetrics();

  /// Отступ от края окна до панелей и зазор между панелями.
  double get windowPadding => 3;
  double get panelGap => 3;

  /// «Плашка» с путём: наполовину заходит на верхнюю рамку панели.
  double get pathHeaderHeight => 21;
  double get pathHeaderRadius => 3;
  double get pathHeaderMinInset => 20;

  /// Отступ от рамки панели до строки заголовков.
  double get panelTopPadding => 22;

  double get headerRowHeight => 26;
  double get rowHeight => 20;
  double get statusBarHeight => 30;

  double get functionBarHeight => 27;
  double get functionButtonHeight => 21;
  double get functionButtonRadius => 3;
  double get functionBarGap => 8;

  /// Ширина полосы, отмечающей помеченный объект у левого края строки.
  double get markedBarWidth => 3;

  double get cellPadding => 6;
  double get iconSize => 16;
  double get fontSize => 12;

  /// Ширина области захвата разделителя панелей и границ колонок.
  double get resizeHandleWidth => 7;

  /// Минимальная ширина панели при перетаскивании разделителя.
  double get minPanelWidth => 200;
}
