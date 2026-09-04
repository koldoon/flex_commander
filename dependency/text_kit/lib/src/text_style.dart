import 'package:flutter/painting.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';

import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'syntax_theme.dart';

/// Высота строки текста в просмотрщике и редакторе — множитель к кеглю.
///
/// Задаётся явно, а не оставляется на усмотрение `re_editor`: в нашей копии
/// библиотеки шаг строк меряется струной (`dependency/re_editor/README.md`), и
/// при её умолчании `1.4` строки сошлись бы теснее, чем были. `1.6` даёт ровно
/// тот же шаг, что был до починки, — 19 точек при кегле 13.6. Проверено
/// замером: `test/rendering/line_grid_test.dart`.
const double textLineHeight = 1.6;

/// Оформление текстового поля из темы приложения.
///
/// Одно на двоих: просмотрщик и редактор показывают один и тот же файл и
/// обязаны показывать его одинаково. Раньше это было договорённостью — теперь
/// следствие: цвета, шрифт и высота строки собираются здесь.
///
/// Языков ровно один — тот, что опознан по имени файла: регистрировать все две
/// сотни ради одного файла незачем.
///
/// **Своего фона у текста нет.** Фон места рисует рамка (`FcPanelFrame`), и
/// второй раз его не кладут: чей это фон — решает тот, кто отвёл место, а не
/// то, что в него положили. Прежде за это наказывали сразу — `panelBackground`
/// был белым в пять процентов, и второй слой давал полтона разницы с панелью;
/// теперь цвет непрозрачный ([FcPalette.panel]), и ошибка стала тихой. Правило
/// от этого не изменилось. `null` здесь означает «не красить».
CodeEditorStyle textViewStyle(FcTheme theme, TextStyle base, String? language) {
  final colors = theme.colors;
  final mode = language == null ? null : builtinAllLanguages[language];

  return CodeEditorStyle(
    fontFamily: base.fontFamily,
    // Запасные семейства едут вместе со шрифтом: в просмотрщике и редакторе
    // подстановка нужна ровно та же, что в списке файлов.
    fontFamilyFallback: base.fontFamilyFallback,
    fontSize: base.fontSize,
    // Высота строки — своя, а не умолчание библиотеки: см. `textLineHeight`.
    fontHeight: textLineHeight,
    textColor: colors.rowText,
    cursorColor: colors.markedBar,
    // Толщина курсора общая на всё приложение — своей у редактора нет.
    cursorWidth: theme.metrics.caretWidth,
    selectionColor: colors.inputSelection,
    // Язык не опознан — темы подсветки нет вовсе, а не пустая.
    //
    // Пустая карта языков роняет разбор: он считает по ней минимальный размер
    // файла (`reduce`) и падает на пустом списке — в изоляте, то есть молча и
    // мимо любого нашего try. Наткнулись на `.log`.
    codeTheme:
        mode == null
            ? null
            : CodeHighlightTheme(
              languages: {language!: CodeHighlightThemeMode(mode: mode)},
              theme: syntaxTheme(colors, base),
            ),
  );
}

/// Основной стиль текста: моноширинный шрифт темы её же кеглем и цветом.
TextStyle textBaseStyle(FcTheme theme) => theme.fixedStyle.copyWith(color: theme.colors.rowText);
