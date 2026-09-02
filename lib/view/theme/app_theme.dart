import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

/// Собирает тему Flutter из выбранного оформления.
///
/// Приложение рисуется своими виджетами, поэтому от `ThemeData` нужно немногое:
/// донести до дерева [FcTheme] и настроить то, что рисует сам Flutter, —
/// полосы прокрутки и выделение в поле ввода.
ThemeData buildThemeData(FcThemeSpec spec) {
  final theme = spec.theme;
  final colors = spec.colors;

  return ThemeData(
    brightness: spec.brightness,
    useMaterial3: true,
    fontFamily: spec.fonts.ui,
    scaffoldBackgroundColor: colors.windowBackground,
    extensions: [theme],
    // Списки и панели прокручиваются без «эффекта растяжения»: это
    // настольное приложение, а не мобильное.
    scrollbarTheme: const ScrollbarThemeData(thickness: WidgetStatePropertyAll(8)),
    textSelectionTheme: TextSelectionThemeData(cursorColor: colors.inputText, selectionColor: colors.inputSelection),
  );
}
