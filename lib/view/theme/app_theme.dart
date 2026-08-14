import 'package:flutter/material.dart';

import '../../model/settings/app_settings.dart';
import 'app_colors.dart';
import 'app_metrics.dart';

/// Палитра, метрики и стили текста приложения.
///
/// Доступ — через [FcTheme.of]; хардкод цветов и размеров в виджетах не нужен.
class FcTheme extends ThemeExtension<FcTheme> {
  const FcTheme({required this.colors, required this.metrics});

  final FcColors colors;
  final FcMetrics metrics;

  static FcTheme of(BuildContext context) => Theme.of(context).extension<FcTheme>()!;

  /// Базовый стиль строки списка.
  TextStyle get rowStyle => TextStyle(fontSize: metrics.fontSize, color: colors.rowText, height: 1.2);

  /// Стиль для колонок с числами и датами: цифры одинаковой ширины, иначе
  /// столбец «прыгает» при прокрутке.
  TextStyle get numericStyle => rowStyle.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  TextStyle get headerStyle => TextStyle(fontSize: metrics.fontSize, color: colors.headerText, height: 1.2);

  TextStyle get statusStyle => TextStyle(fontSize: metrics.fontSize, color: colors.rowText, height: 1.2);

  TextStyle get pathStyle =>
      TextStyle(fontSize: metrics.fontSize, color: colors.pathText, fontWeight: FontWeight.w600, height: 1.2);

  @override
  FcTheme copyWith({FcColors? colors, FcMetrics? metrics}) =>
      FcTheme(colors: colors ?? this.colors, metrics: metrics ?? this.metrics);

  /// Между темами не анимируем: мигание палитрой в файловом менеджере ни к чему.
  @override
  FcTheme lerp(covariant FcTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light = _build(Brightness.light, FcColors.light);

  static ThemeData dark = _build(Brightness.dark, FcColors.dark);

  static ThemeData _build(Brightness brightness, FcColors colors) {
    const metrics = FcMetrics();
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: colors.windowBackgroundBottom,
      extensions: [FcTheme(colors: colors, metrics: metrics)],
      // Списки и панели прокручиваются без «эффекта растяжения»: это
      // настольное приложение, а не мобильное.
      scrollbarTheme: const ScrollbarThemeData(thickness: WidgetStatePropertyAll(8)),
    );
  }

  static ThemeMode themeModeOf(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}
