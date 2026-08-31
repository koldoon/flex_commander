import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Моноширинный набор: семейство вместе с запасными.
void main() {
  const theme = FcTheme(
    colors: DefaultColors(),
    metrics: DefaultMetrics(),
    icons: DefaultIcons(),
    fonts: DefaultFonts(),
  );

  test('запасные семейства идут вместе с основным', () {
    // Порознь их брать нельзя: шрифт списка берётся из системы, и на машине,
    // где его нет, подстановку выбирает тот, кто рисует. Flutter возьмёт свою,
    // `xterm` — свою, и один и тот же текст выйдет разными шрифтами: видно по
    // приглашению в терминале, которое стоит на пару пикселей врозь с таким же
    // приглашением в командной строке.
    expect(theme.fixedStyle.fontFamily, theme.fonts.fixed);
    expect(theme.fixedStyle.fontFamilyFallback, theme.fonts.fixedFallback);
    expect(theme.fixedStyle.fontSize, theme.metrics.fontSize);
  });

  test('строка списка набирается им же', () {
    // Иначе панель и строка разойдутся ровно так же, как разошлись терминал и
    // командная строка.
    expect(theme.rowStyle.fontFamily, theme.fixedStyle.fontFamily);
    expect(theme.rowStyle.fontFamilyFallback, theme.fixedStyle.fontFamilyFallback);
    expect(theme.rowStyle.fontSize, theme.fixedStyle.fontSize);
  });
}
