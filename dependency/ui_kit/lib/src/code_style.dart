import 'package:flutter/painting.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';

import 'fc_theme.dart';
import 'syntax_theme.dart';

/// Оформление текстового поля из темы приложения.
///
/// Одно на двоих: просмотрщик и редактор показывают один и тот же файл и
/// обязаны показывать его одинаково. Раньше это было договорённостью — теперь
/// следствие: цвета, шрифт и высота строки собираются здесь.
///
/// Языков ровно один — тот, что опознан по имени файла: регистрировать все две
/// сотни ради одного файла незачем.
///
/// **Своего фона у текста нет.** Фон панели (`panelBackground`) — это белый с
/// прозрачностью пять процентов поверх фона окна, и рисует его рамка
/// (`FcPanelFrame`). Положить тот же цвет ещё раз внутри значит сложить
/// прозрачности: получается полтона разницы с панелью — ровно то, что видно
/// глазом и не видно в коде. `null` здесь означает «не красить».
CodeEditorStyle codeStyle(FcTheme theme, TextStyle base, String? language) {
  final colors = theme.colors;
  final mode = language == null ? null : builtinAllLanguages[language];

  return CodeEditorStyle(
    fontFamily: base.fontFamily,
    fontSize: base.fontSize,
    // Высота строки — своя, а не умолчание библиотеки: см. `codeFontHeight`.
    fontHeight: codeFontHeight,
    textColor: colors.rowText,
    cursorColor: colors.markedBar,
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
TextStyle codeBaseStyle(FcTheme theme) =>
    TextStyle(fontFamily: theme.fonts.fixed, fontSize: theme.metrics.fontSize, color: theme.colors.rowText);
