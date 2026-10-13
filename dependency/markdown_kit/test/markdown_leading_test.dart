import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Интерлиньяж и отбивка абзацев (`docs/spec/markdown-viewer.md`, §6).
void main() {
  final theme = FcTheme(
    colors: DefaultColors(),
    metrics: DefaultMetrics(),
    icons: DefaultIcons(),
    fonts: DefaultFonts(),
  );

  test('абзац набран просторнее подписи окна', () {
    expect(fcMarkdownStyle(theme).p!.height, fcMarkdownLineHeight);
    expect(fcMarkdownLineHeight, inInclusiveRange(1.2, 1.5), reason: 'Баттерик — 120–145 %, GitHub — 1,5');
  });

  test('между абзацами просвет заметно больше, чем между строками', () {
    final style = fcMarkdownStyle(theme);
    final size = style.p!.fontSize!;
    // Между строками абзаца — добавка интерлиньяжа; между абзацами — она же и
    // отбивка блока сверху.
    final betweenLines = size * (fcMarkdownLineHeight - 1);
    final betweenParagraphs = betweenLines + style.blockSpacing!;

    expect(betweenParagraphs, greaterThanOrEqualTo(betweenLines * 2));
  });

  test('всё, что стоит в строке, — одной высоты строки', () {
    final style = fcMarkdownStyle(theme);
    for (final inline in [style.strong, style.em, style.a, style.code, style.listBullet]) {
      expect(inline!.height, style.p!.height);
    }
  });
}
