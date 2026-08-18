import '../serialization.dart';

/// Положение и размер окна приложения.
class WindowGeometry implements Serializable {
  WindowGeometry({this.left = 0, this.top = 0, this.width = 1000, this.height = 700, this.maximized = false});

  /// Минимальный размер окна: при меньшем панели становятся нечитаемыми.
  static const double minWidth = 640;
  static const double minHeight = 400;

  /// Умолчания — каждый раз новым экземпляром: поля изменяемые, и общий
  /// экземпляр однажды поменяли бы сразу всем.
  static WindowGeometry get defaults => WindowGeometry();

  double left;
  double top;
  double width;
  double height;

  /// Окно развёрнуто. Тогда положение и размер — это то, к чему окно вернётся
  /// после сворачивания, поэтому они сохраняются всё равно.
  bool maximized;

  WindowGeometry copyWith({double? left, double? top, double? width, double? height, bool? maximized}) =>
      WindowGeometry(
        left: left ?? this.left,
        top: top ?? this.top,
        width: width ?? this.width,
        height: height ?? this.height,
        maximized: maximized ?? this.maximized,
      );

  @override
  void toMap(Map<String, dynamic> m) {
    m['left'] = left;
    m['top'] = top;
    m['width'] = width;
    m['height'] = height;
    m['maximized'] = maximized;
  }

  /// Неполные или бессмысленные значения (нулевой размер, мусор вместо чисел)
  /// остаются умолчаниями: окно должно открыться в любом случае.
  ///
  /// Отсутствующий ключ значение не меняет — на этом держится весь разбор
  /// настроек, поэтому размеры доводятся до разумных отдельно.
  @override
  void fromMap(Map<String, dynamic> m) {
    left = extract(left, m['left']);
    top = extract(top, m['top']);
    width = _sane(extract(width, m['width']), defaults.width, minWidth);
    height = _sane(extract(height, m['height']), defaults.height, minHeight);
    maximized = extract(maximized, m['maximized']);
  }

  static double _sane(double value, double fallback, double minimum) {
    if (!value.isFinite || value <= 0) {
      return fallback;
    }
    return value < minimum ? minimum : value;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowGeometry &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height &&
      other.maximized == maximized;

  @override
  int get hashCode => Object.hash(left, top, width, height, maximized);

  @override
  String toString() => 'WindowGeometry($left, $top, $width×$height, maximized: $maximized)';
}
