import 'package:flutter/widgets.dart';

/// Иконки референсного приложения — `resources/styles/icon.as`.
///
/// Это глифы FontAwesome, и рисуются они как текст, а не как картинки: в
/// референсе иконка была обычной меткой со шрифтом `icon_cff`. Отсюда и
/// [FcIcons.fontFamily] — им же красится и масштабируется всё остальное.
abstract final class FcIcons {
  static const String fontFamily = 'FontAwesome';

  static const IconData folder = IconData(0xf07b, fontFamily: fontFamily);
  static const IconData folderOpen = IconData(0xf114, fontFamily: fontFamily);
  static const IconData link = IconData(0xf0c1, fontFamily: fontFamily);
  static const IconData asterisk = IconData(0xf069, fontFamily: fontFamily);
  static const IconData check = IconData(0xf00c, fontFamily: fontFamily);

  /// Стрелка «ведёт на» — в описании ссылки.
  ///
  /// Не `long-arrow-right`: та почти целую кегельную площадку в ширину
  /// (0.96 em против 0.33) и рядом с именем выглядит растянутой.
  static const IconData angleRight = IconData(0xf105, fontFamily: fontFamily);

  /// Направление сортировки в заголовке колонки.
  static const IconData caretUp = IconData(0xf0d8, fontFamily: fontFamily);
  static const IconData caretDown = IconData(0xf0d7, fontFamily: fontFamily);

  /// Кружок, которым в референсе **измеряли** ширину места под иконку: у
  /// обычного файла иконки нет, но колонка имён должна начинаться одинаково.
  static const IconData circleOutline = IconData(0xf10c, fontFamily: fontFamily);

  /// Битая ссылка: в референсе такого случая не было.
  static const IconData exclamation = IconData(0xf12a, fontFamily: fontFamily);

  /// Глиф строкой — для мест, где иконка идёт внутри текста, а не отдельным
  /// виджетом: например, стрелка в описании ссылки.
  static String glyph(IconData icon) => String.fromCharCode(icon.codePoint);
}
