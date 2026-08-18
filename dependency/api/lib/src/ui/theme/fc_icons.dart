import 'package:flutter/widgets.dart';

/// Иконки приложения — глифы шрифта, а не картинки.
///
/// Рисуются как текст: в референсе (`resources/styles/icon.as`) иконка была
/// обычной меткой со шрифтом `icon_cff`. Отсюда и [fontFamily] — им же
/// красится и масштабируется всё остальное.
///
/// Класс обычный, с виртуальными геттерами: тема подменяет и отдельную иконку,
/// и весь шрифт целиком — так же, как цвета и метрики.
class FcIcons {
  const FcIcons({this.fontFamily = defaultFontFamily});

  /// Шрифт иконок по умолчанию — тот же, что в референсе.
  static const String defaultFontFamily = 'FontAwesome';

  /// Шрифт, из которого берутся глифы.
  final String fontFamily;

  IconData get folder => _icon(0xf07b);

  IconData get folderOpen => _icon(0xf114);

  IconData get link => _icon(0xf0c1);

  IconData get asterisk => _icon(0xf069);

  IconData get check => _icon(0xf00c);

  /// Стрелка «ведёт на» — в описании ссылки.
  ///
  /// Не `long-arrow-right`: та почти целую кегельную площадку в ширину
  /// (0.96 em против 0.33) и рядом с именем выглядит растянутой.
  IconData get angleRight => _icon(0xf105);

  /// Направление сортировки в заголовке колонки.
  IconData get caretUp => _icon(0xf0d8);

  IconData get caretDown => _icon(0xf0d7);

  /// Кружок, которым в референсе **измеряли** ширину места под иконку: у
  /// обычного файла иконки нет, но колонка имён должна начинаться одинаково.
  IconData get circleOutline => _icon(0xf10c);

  /// Битая ссылка: в референсе такого случая не было.
  IconData get exclamation => _icon(0xf12a);

  /// Глиф строкой — для мест, где иконка идёт внутри текста, а не отдельным
  /// виджетом: например, стрелка в описании ссылки.
  String glyph(IconData icon) => String.fromCharCode(icon.codePoint);

  // Анализатор предлагает сделать IconData константой — но именно этого мы и
  // не хотим: шрифт берётся у темы, а она известна только во время работы.
  // ignore: non_const_argument_for_const_parameter
  IconData _icon(int codePoint) => IconData(codePoint, fontFamily: fontFamily);
}
