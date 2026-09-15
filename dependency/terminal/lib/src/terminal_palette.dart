import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Оформление терминала: наша тема, разложенная так, как её ждёт `xterm`.
///
/// Одна на два места — развёрнутый терминал (`Ctrl-O`) и приглашение в строке
/// команд: одно и то же приглашение не должно различаться цветом ни на тон
/// (`docs/spec/shell-prompt.md`, §5).
TerminalTheme terminalThemeOf(FcTheme theme) {
  final colors = theme.colors;
  final ansi = colors.terminalAnsi;

  return TerminalTheme(
    cursor: colors.terminalCursor,
    selection: colors.terminalSelection,
    foreground: colors.terminalText,
    // Фон рисует не терминал, а место под ним: вид стоит прозрачным поверх
    // фона окна (`backgroundOpacity: 0`).
    background: colors.windowBackground,
    black: ansi[0],
    red: ansi[1],
    green: ansi[2],
    yellow: ansi[3],
    blue: ansi[4],
    magenta: ansi[5],
    cyan: ansi[6],
    white: ansi[7],
    brightBlack: ansi[8],
    brightRed: ansi[9],
    brightGreen: ansi[10],
    brightYellow: ansi[11],
    brightBlue: ansi[12],
    brightMagenta: ansi[13],
    brightCyan: ansi[14],
    brightWhite: ansi[15],
    // Поиск по экрану терминала мы не показываем; роли названы тем, чем
    // приложение показывает найденное вообще.
    searchHitBackground: colors.markedBackground,
    searchHitBackgroundCurrent: colors.cursorBackground,
    searchHitForeground: colors.cursorText,
  );
}

/// Цвет ячейки буфера — числом, как его хранит `xterm`, и цветом, как его
/// рисует терминал.
///
/// Таблица на 256 цветов повторяет `PaletteBuilder` из `xterm` **дословно**,
/// включая его странность на номере 15 (там отдаётся обычный белый, а не
/// яркий). Повторяется она нарочно: нам нужно не «правильно», а **так же** —
/// иначе приглашение в строке и в терминале разошлись бы на один цвет, и
/// объяснить это было бы нечем. Своя таблица понадобилась потому, что чужая из
/// библиотеки не вынесена наружу.
class TerminalPalette {
  TerminalPalette(this.theme) : _table = List.generate(256, (index) => _colorAt(theme, index), growable: false);

  final TerminalTheme theme;
  final List<Color> _table;

  /// Чем набран текст этой ячейки.
  Color textOf(int cellColor) => _resolve(cellColor, theme.foreground);

  /// Чем залита эта ячейка.
  Color backgroundOf(int cellColor) => _resolve(cellColor, theme.background);

  Color _resolve(int cellColor, Color own) {
    final value = cellColor & CellColor.valueMask;
    return switch (cellColor & CellColor.typeMask) {
      CellColor.normal => own,
      CellColor.named || CellColor.palette => _table[value],
      _ => Color(value | 0xFF000000),
    };
  }

  static Color _colorAt(TerminalTheme theme, int index) {
    const named = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
    if (named.contains(index)) {
      return switch (index) {
        0 => theme.black,
        1 => theme.red,
        2 => theme.green,
        3 => theme.yellow,
        4 => theme.blue,
        5 => theme.magenta,
        6 => theme.cyan,
        7 => theme.white,
        8 => theme.brightBlack,
        9 => theme.brightRed,
        10 => theme.brightGreen,
        11 => theme.brightYellow,
        12 => theme.brightBlue,
        13 => theme.brightMagenta,
        14 => theme.brightCyan,
        // Не `brightWhite` — так в `xterm`, и расходиться с ним нельзя.
        _ => theme.white,
      };
    }

    if (index < 232) {
      // Куб 6×6×6: шаг 95, дальше по 40 — как договорено в ANSI.
      const steps = [0, 95, 135, 175, 215, 255];
      final at = index - 16;
      return Color.fromARGB(0xFF, steps[at ~/ 36], steps[(at ~/ 6) % 6], steps[at % 6]);
    }

    // Двадцать четыре серых: от 8 с шагом 10.
    final gray = 8 + (index - 232) * 10;
    return Color.fromARGB(0xFF, gray, gray, gray);
  }
}
