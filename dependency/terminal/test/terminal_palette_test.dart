import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
// Чужая внутренность — нарочно: сверяемся с той самой таблицей, которой
// рисует терминал. Наружу она не вынесена, а сверить надо именно её: нам нужно
// не «правильно», а **так же** (`docs/spec/shell-prompt.md`, §5).
// ignore: implementation_imports
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/xterm.dart';

/// Палитра терминала: одна на развёрнутый терминал и на строку команд.
void main() {
  final theme = FcTheme(
    colors: DefaultColors(),
    metrics: DefaultMetrics(),
    icons: DefaultIcons(),
    fonts: DefaultFonts(),
  );

  final terminalTheme = terminalThemeOf(theme);
  final palette = TerminalPalette(terminalTheme);

  test('таблица совпадает с той, которой рисует терминал, все 256 цветов', () {
    final theirs = PaletteBuilder(terminalTheme).build();

    for (var index = 0; index < 256; index++) {
      expect(
        palette.textOf(CellColor.palette | index),
        theirs[index],
        reason: 'цвет $index расходится: одно и то же приглашение выглядело бы по-разному',
      );
    }
  });

  test('цвет без своего номера — цвет вывода из темы', () {
    expect(palette.textOf(CellColor.normal), const DefaultColors().terminalText);
    expect(palette.backgroundOf(CellColor.normal), const DefaultColors().windowBackground);
  });

  test('прямой RGB берётся как есть', () {
    expect(palette.textOf(CellColor.rgb | 0x336699), const Color(0xFF336699));
  });

  test('шестнадцать цветов ANSI приходят из темы', () {
    const colors = DefaultColors();
    expect(colors.terminalAnsi.length, 16);
    expect(palette.textOf(CellColor.named | 1), colors.terminalAnsi[1], reason: 'красный');
    expect(palette.textOf(CellColor.named | 12), colors.terminalAnsi[12], reason: 'яркий синий');
  });
}
