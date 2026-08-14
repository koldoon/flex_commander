/// Положение и размер окна приложения.
class WindowGeometry {
  const WindowGeometry({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.maximized = false,
  });

  /// Минимальный размер окна: при меньшем панели становятся нечитаемыми.
  static const double minWidth = 640;
  static const double minHeight = 400;

  static const WindowGeometry defaults = WindowGeometry(left: 0, top: 0, width: 1000, height: 700);

  final double left;
  final double top;
  final double width;
  final double height;

  /// Окно развёрнуто. Тогда положение и размер — это то, к чему окно вернётся
  /// после сворачивания, поэтому они сохраняются всё равно.
  final bool maximized;

  WindowGeometry copyWith({double? left, double? top, double? width, double? height, bool? maximized}) =>
      WindowGeometry(
        left: left ?? this.left,
        top: top ?? this.top,
        width: width ?? this.width,
        height: height ?? this.height,
        maximized: maximized ?? this.maximized,
      );

  Map<String, Object?> toJson() => {'left': left, 'top': top, 'width': width, 'height': height, 'maximized': maximized};

  /// Разбор из настроек. Неполные или бессмысленные значения (нулевой размер,
  /// мусор вместо чисел) заменяются умолчаниями: окно должно открыться в любом
  /// случае.
  static WindowGeometry? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }

    final width = _positive(json['width'], defaults.width, minWidth);
    final height = _positive(json['height'], defaults.height, minHeight);
    final left = json['left'];
    final top = json['top'];
    final maximized = json['maximized'];

    return WindowGeometry(
      left: left is num ? left.toDouble() : defaults.left,
      top: top is num ? top.toDouble() : defaults.top,
      width: width,
      height: height,
      maximized: maximized is bool ? maximized : false,
    );
  }

  static double _positive(Object? value, double fallback, double minimum) {
    if (value is! num || !value.isFinite || value <= 0) {
      return fallback;
    }
    return value.toDouble() < minimum ? minimum : value.toDouble();
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
