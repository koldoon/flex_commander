import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_metrics.dart';

/// Палитра, метрики и стили текста приложения.
///
/// Доступ — через [FcTheme.of]; хардкод цветов и размеров в виджетах не нужен.
///
/// Шрифты те же, что в референсе (`resources/styles/typo.css`): интерфейс —
/// Ubuntu, списки файлов — Consolas, иконки — FontAwesome. Они лежат в
/// `assets/fonts`, поэтому приложение выглядит одинаково на любой системе,
/// а не только там, где эти шрифты установлены.
class FcTheme extends ThemeExtension<FcTheme> {
  const FcTheme({this.colors = const FcColors(), this.metrics = const FcMetrics()});

  final FcColors colors;
  final FcMetrics metrics;

  /// Шрифт интерфейса: заголовки, подписи, кнопки, окна команд.
  static const String uiFont = 'Ubuntu';

  /// Шрифт списка файлов: имена, размеры и даты стоят ровными столбцами.
  static const String fixedFont = 'Consolas';

  static FcTheme of(BuildContext context) => Theme.of(context).extension<FcTheme>()!;

  /// Базовый стиль интерфейса.
  TextStyle get uiStyle =>
      TextStyle(fontFamily: uiFont, fontSize: metrics.fontSize, color: colors.rowText, height: 1.2);

  /// Строка списка файлов.
  TextStyle get rowStyle =>
      TextStyle(fontFamily: fixedFont, fontSize: metrics.fontSize, color: colors.rowText, height: 1.2);

  /// Колонки с числами и датами. Consolas моноширинный, поэтому отдельная
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
  FcTheme copyWith({FcColors? colors, FcMetrics? metrics}) =>
      FcTheme(colors: colors ?? this.colors, metrics: metrics ?? this.metrics);

  /// Тема одна, поэтому переходить не к чему.
  @override
  FcTheme lerp(covariant FcTheme? other, double t) => other ?? this;
}

/// Тема приложения — одна, как у референсного приложения.
class AppTheme {
  const AppTheme._();

  static final ThemeData theme = _build();

  static ThemeData _build() {
    const colors = FcColors();
    const metrics = FcMetrics();

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: FcTheme.uiFont,
      scaffoldBackgroundColor: colors.windowBackground,
      extensions: const [FcTheme(colors: colors, metrics: metrics)],
      // Списки и панели прокручиваются без «эффекта растяжения»: это
      // настольное приложение, а не мобильное.
      scrollbarTheme: const ScrollbarThemeData(thickness: WidgetStatePropertyAll(8)),
      textSelectionTheme: TextSelectionThemeData(cursorColor: colors.inputText, selectionColor: colors.inputSelection),
    );
  }
}
