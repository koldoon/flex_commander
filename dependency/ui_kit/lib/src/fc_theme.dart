import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';

/// Оформление: палитра, метрики, иконки, шрифты и стили текста.
///
/// Доступ — через [FcTheme.of]; хардкод цветов и размеров в виджетах не нужен.
/// Значений по умолчанию здесь нет: их приносит тема, а API описывает только
/// роли. Готовое оформление — в модуле `fc_default_theme`.
class FcTheme extends ThemeExtension<FcTheme> {
  const FcTheme({required this.colors, required this.metrics, required this.icons, required this.fonts});

  final FcColors colors;
  final FcMetrics metrics;
  final FcIcons icons;
  final FcFonts fonts;

  static FcTheme of(BuildContext context) => Theme.of(context).extension<FcTheme>()!;

  /// Базовый стиль интерфейса.
  TextStyle get uiStyle =>
      TextStyle(fontFamily: fonts.ui, fontSize: metrics.fontSize, color: colors.rowText, height: 1.2);

  /// Строка списка файлов.
  TextStyle get rowStyle =>
      TextStyle(fontFamily: fonts.fixed, fontSize: metrics.fontSize, color: colors.rowText, height: 1.2);

  /// Колонки с числами и датами. Шрифт списка моноширинный, поэтому отдельная
  /// настройка цифр не нужна — столбец и так не «прыгает».
  TextStyle get numericStyle => rowStyle;

  TextStyle get headerStyle => uiStyle.copyWith(color: colors.headerText);

  TextStyle get statusStyle => uiStyle;

  TextStyle get pathStyle => uiStyle.copyWith(color: colors.pathText);

  /// Заголовок окна команды: `styleName="white bold left h5"`.
  TextStyle get dialogTitleStyle => uiStyle.copyWith(color: colors.dialogTitleText, fontWeight: FontWeight.bold);

  /// Подпись поля в окне команды.
  TextStyle get dialogLabelStyle => uiStyle.copyWith(color: colors.dialogLabel);

  /// Значение в окне команды.
  TextStyle get dialogTextStyle => uiStyle.copyWith(color: colors.dialogText);

  TextStyle get buttonStyle => uiStyle.copyWith(color: colors.buttonText);

  TextStyle get inputStyle => uiStyle.copyWith(color: colors.inputText);

  @override
  FcTheme copyWith({FcColors? colors, FcMetrics? metrics, FcIcons? icons, FcFonts? fonts}) => FcTheme(
    colors: colors ?? this.colors,
    metrics: metrics ?? this.metrics,
    icons: icons ?? this.icons,
    fonts: fonts ?? this.fonts,
  );

  /// Темы переключаются целиком и сразу: плавный переход между палитрами
  /// файловому менеджеру ни к чему, а половинчатое состояние сбивало бы с толку.
  @override
  FcTheme lerp(covariant FcTheme? other, double t) => other ?? this;
}

/// Значения темы в виде расширения, которое виджеты достают через [FcTheme.of].
///
/// Расширением, а не полем в самой [FcThemeSpec]: спецификация живёт в API и
/// говорит, какие роли есть, — а собирать из них тему для дерева виджетов
/// умеет тот, кто виджеты и рисует.
extension FcThemeOfSpec on FcThemeSpec {
  FcTheme get theme => FcTheme(colors: colors, metrics: metrics, icons: icons, fonts: fonts);
}
