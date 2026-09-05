import 'package:flutter/widgets.dart';

/// Иконки приложения — глифы шрифта, а не картинки.
///
/// Рисуются как текст: в референсе (`resources/styles/icon.as`) иконка была
/// обычной меткой со шрифтом `icon_cff`. Отсюда и [fontFamily] — им же
/// красится и масштабируется всё остальное.
///
/// Здесь только роли: какая иконка что означает. Сами глифы и шрифт приносит
/// тема — так же, как цвета и размеры.
abstract class FcIcons {
  const FcIcons();

  /// Шрифт, из которого берутся глифы.
  String get fontFamily;

  IconData get folder;

  IconData get folderOpen;

  IconData get link;

  IconData get asterisk;

  IconData get check;

  /// Стрелка «ведёт на» — в описании ссылки.
  ///
  /// Не `long-arrow-right`: та почти целую кегельную площадку в ширину
  /// (0.96 em против 0.33) и рядом с именем выглядит растянутой.
  IconData get angleRight;

  /// Направление сортировки в заголовке колонки.
  IconData get caretUp;

  IconData get caretDown;

  /// Кружок, которым в референсе **измеряли** ширину места под иконку: у
  /// обычного файла иконки нет, но колонка имён должна начинаться одинаково.
  IconData get circleOutline;

  /// Битая ссылка: в референсе такого случая не было.
  IconData get exclamation;
}

/// Роль по имени — для правил, приехавших из файла настроек.
///
/// Имена те же, что у геттеров: `glyph:folder` в правиле иконки означает
/// [FcIcons.folder]. Незнакомое имя даёт null, и правило с ним пропускается —
/// файл настроек правят руками (`docs/spec/file-icons.md`, §4).
extension FcIconRoles on FcIcons {
  IconData? byRole(String role) => switch (role) {
    'folder' => folder,
    'folderOpen' => folderOpen,
    'link' => link,
    'asterisk' => asterisk,
    'check' => check,
    'angleRight' => angleRight,
    'caretUp' => caretUp,
    'caretDown' => caretDown,
    'circleOutline' => circleOutline,
    'exclamation' => exclamation,
    _ => null,
  };
}

/// Глиф строкой — для мест, где иконка идёт внутри текста, а не отдельным
/// виджетом: например, стрелка в описании ссылки.
extension FcIconGlyph on FcIcons {
  String glyph(IconData icon) => String.fromCharCode(icon.codePoint);
}
