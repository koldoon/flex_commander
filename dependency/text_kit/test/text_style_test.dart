import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оформление показа текста: то, что нельзя проверить виджетом, проверяется здесь.
void main() {
  const theme = FcTheme(
    colors: DefaultColors(),
    metrics: DefaultMetrics(),
    icons: DefaultIcons(),
    fonts: DefaultFonts(),
  );
  const base = TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Menlo'], fontSize: 13);

  test('своего фона у показа нет: его рисует рамка', () {
    // Фон места кладёт рамка, и второй раз его не кладут: чей это фон — решает
    // тот, кто отвёл место. Пока `panelBackground` был прозрачным, второй слой
    // вдобавок красил мимо — на полтона светлее панели.
    final style = textViewStyle(theme, base, 'sql');

    expect(style.backgroundColor, isNull);
  });

  test('шрифт и цвет текста — из темы, а не свои', () {
    final style = textViewStyle(theme, base, null);

    expect(style.fontFamily, base.fontFamily);
    expect(style.fontSize, base.fontSize);
    expect(style.textColor, const DefaultColors().rowText);
  });

  group('подсветка', () {
    test('регистрируется ровно один язык — опознанный', () {
      final style = textViewStyle(theme, base, 'sql');

      expect(style.codeTheme?.languages.keys, ['sql']);
    });

    test('язык не опознан — темы нет вовсе, но текст показывается', () {
      // Не пустая карта языков, а именно `null`: по пустой разбор считает
      // минимум `reduce`-ом и падает на пустом списке — в изоляте, молча.
      final style = textViewStyle(theme, base, null);

      expect(style.codeTheme, isNull);
      expect(style.textColor, isNotNull);
    });

    test('цвета токенов — из общей карты', () {
      final style = textViewStyle(theme, base, 'dart');
      final shared = syntaxTheme(const DefaultColors(), base);

      expect(style.codeTheme?.theme['keyword']?.color, shared['keyword']?.color);
      expect(style.codeTheme?.theme['string']?.color, const DefaultColors().syntaxString);
    });
  });
}
