import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Моноширинный набор: семейство вместе с запасными.
void main() {
  final theme = FcTheme(
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

  test('межстрочная — та же, что у терминала', () {
    // Без неё текст встаёт по собственной метрике шрифта, а `xterm` всегда
    // ставит свою: одна и та же строка в терминале и в командной строке
    // оказывается на пару пикселей врозь.
    // Что число то же самое, что у `xterm`, стережёт тест в модуле терминала:
    // здесь про `xterm` не знают и знать не должны.
    expect(theme.fixedStyle.height, FcTheme.terminalLineHeight);
  });

  test('строка списка по умолчанию набирается им же', () {
    // Тема, не назвавшая шрифт списка, выглядит как раньше: иначе панель и
    // строка разойдутся ровно так же, как разошлись терминал и командная
    // строка.
    expect(theme.rowStyle.fontFamily, theme.fixedStyle.fontFamily);
    expect(theme.rowStyle.fontFamilyFallback, theme.fixedStyle.fontFamilyFallback);
    expect(theme.rowStyle.fontSize, theme.fixedStyle.fontSize);
  });

  group('свой шрифт списка (`docs/spec/list-font.md`)', () {
    final custom = FcTheme(
      colors: DefaultColors(),
      metrics: DefaultMetrics(),
      icons: DefaultIcons(),
      fonts: const _ListFont(DefaultFonts(), 'Ubuntu'),
    );

    test('меняет строку списка, а код и терминал остаются моноширинными', () {
      expect(custom.rowStyle.fontFamily, 'Ubuntu');
      expect(custom.fixedStyle.fontFamily, 'Consolas', reason: 'код, терминал и просмотр — моноширинным');
    });

    test('не нашлось — список набирается моноширинным темы', () {
      expect(custom.rowStyle.fontFamilyFallback, ['Consolas', 'Menlo']);
    });

    test('высота строки от выбора шрифта не прыгает', () {
      expect(custom.rowStyle.height, custom.fixedStyle.height);
      expect(custom.rowStyle.fontSize, custom.fixedStyle.fontSize);
    });
  });

  test('цифры списка табличные — столбцы держатся при любом шрифте', () {
    expect(theme.rowStyle.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(theme.numericStyle.fontFeatures, contains(const FontFeature.tabularFigures()));
  });
}

/// Тема со своим шрифтом списка поверх оформления по умолчанию.
class _ListFont extends FcFonts {
  const _ListFont(this.base, this.list);

  final FcFonts base;

  @override
  final String list;

  @override
  String get ui => base.ui;

  @override
  String get fixed => base.fixed;

  @override
  List<String> get fixedFallback => base.fixedFallback;
}
