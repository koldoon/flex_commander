import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оформление редактора: то, что нельзя проверить виджетом, проверяется здесь.
void main() {
  const theme = FcTheme(
    colors: DefaultColors(),
    metrics: DefaultMetrics(),
    icons: DefaultIcons(),
    fonts: DefaultFonts(),
  );
  const base = TextStyle(fontFamily: 'Consolas', fontSize: 13);

  test('своего фона у редактора нет: его рисует рамка', () {
    // Фон панели — белый с прозрачностью пять процентов поверх фона окна.
    // Второй такой же слой внутри редактора сложил бы прозрачности, и экран
    // отличался бы от панели на полтона.
    final style = editorStyle(theme, base, 'sql');

    expect(style.backgroundColor, isNull);
  });

  test('шрифт и цвет текста — из темы, а не свои', () {
    final style = editorStyle(theme, base, null);

    expect(style.fontFamily, base.fontFamily);
    expect(style.fontSize, base.fontSize);
    expect(style.textColor, const DefaultColors().rowText);
  });

  group('подсветка', () {
    test('регистрируется ровно один язык — опознанный', () {
      final style = editorStyle(theme, base, 'sql');

      expect(style.codeTheme?.languages.keys, ['sql']);
    });

    test('язык не опознан — подсветки нет, но текст показывается', () {
      final style = editorStyle(theme, base, null);

      expect(style.codeTheme?.languages, isEmpty);
      expect(style.textColor, isNotNull);
    });

    test('цвета токенов — общие с просмотрщиком', () {
      final style = editorStyle(theme, base, 'dart');
      final shared = syntaxTheme(const DefaultColors(), base);

      expect(style.codeTheme?.theme['keyword']?.color, shared['keyword']?.color);
      expect(style.codeTheme?.theme['string']?.color, const DefaultColors().syntaxString);
    });
  });
}
