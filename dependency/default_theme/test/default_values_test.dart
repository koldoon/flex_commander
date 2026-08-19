import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Значения оформления по умолчанию взяты у референсного приложения.
///
/// Здесь закреплено то, что при правках легко потерять молча: палитра, шрифты
/// и кегль. Проверка живёт рядом со значениями — в API их больше нет.
void main() {
  const colors = DefaultColors();

  group('палитра', () {
    test('фон окна и панели — цвета референса', () {
      expect(colors.windowBackground, FcPalette.blue3);
      expect(colors.panelBackground, FcPalette.white.withValues(alpha: 0.05));
      expect(colors.panelBorder, FcPalette.white.withValues(alpha: 0.15));
    });

    test('курсор, пометка и текст строки', () {
      expect(colors.cursorBackground, FcPalette.blue2);
      expect(colors.cursorText, FcPalette.white);
      expect(colors.markedBar, FcPalette.marker);
      expect(colors.rowText, FcPalette.blue0);
    });

    test('плашка пути и кнопки — цвет sea', () {
      expect(colors.pathBackground, FcPalette.sea);
      expect(colors.functionButtonBackground, FcPalette.sea);
      expect(colors.buttonBackground, FcPalette.sea);
      // Подтверждающая кнопка отличается только заливкой.
      expect(colors.buttonPrimaryBackground, FcPalette.blue1);
    });

    test('окно команды: тело темнее заголовка', () {
      expect(colors.dialogBackground, FcPalette.sea2);
      expect(colors.dialogTitleBackground, FcPalette.sea);
    });
  });

  group('шрифты', () {
    const theme = FcTheme(
      colors: DefaultColors(),
      metrics: DefaultMetrics(),
      icons: DefaultIcons(),
      fonts: DefaultFonts(),
    );

    test('интерфейс набран Ubuntu, список файлов — Consolas', () {
      expect(theme.uiStyle.fontFamily, 'Ubuntu');
      expect(theme.rowStyle.fontFamily, 'Consolas');
      expect(theme.headerStyle.fontFamily, 'Ubuntu');
      expect(theme.buttonStyle.fontFamily, 'Ubuntu');
    });

    test('кегль один на всё приложение: `h5` референса', () {
      final expected = 34 * const DefaultMetrics().fontScale;
      expect(theme.metrics.fontSize, expected);
      for (final style in [theme.uiStyle, theme.rowStyle, theme.headerStyle, theme.pathStyle, theme.buttonStyle]) {
        expect(style.fontSize, expected);
      }
    });

    test('иконки — глифы FontAwesome', () {
      expect(const DefaultIcons().folder.fontFamily, 'FontAwesome');
      expect(const DefaultIcons().folder.codePoint, 0xf07b);
      expect(const DefaultIcons().link.codePoint, 0xf0c1);
      expect(const DefaultIcons().asterisk.codePoint, 0xf069);
      expect(const DefaultIcons().caretUp.codePoint, 0xf0d8);
      expect(const DefaultIcons().caretDown.codePoint, 0xf0d7);
    });
  });

  group('размеры', () {
    const metrics = DefaultMetrics();

    test('выведены из исходников референса одним коэффициентом', () {
      // `height="50"` у строки, `height="60"` у плашки пути и кнопки.
      expect(metrics.rowHeight, 50 * const DefaultMetrics().scale);
      expect(metrics.pathHeaderHeight, 60 * const DefaultMetrics().scale);
      expect(metrics.buttonHeight, 60 * const DefaultMetrics().scale);
    });

    test('кегль мельче, чем даёт коэффициент разметки', () {
      // Замер снимка работающего референса: текст там мельче, чем следует из
      // отношения 34 к 50 в исходниках. Геометрия при этом совпадает.
      expect(const DefaultMetrics().fontScale, lessThan(const DefaultMetrics().scale));
      expect(metrics.fontSize, lessThan(34 * const DefaultMetrics().scale));
      // Иконка — глиф того же кегля, что и текст.
      expect(metrics.iconSize, metrics.fontSize);
    });

    test('колонка иконки вмещает отступ, глиф и просвет до имени', () {
      // Ширина колонки лежит в слое моделей и метрики оттуда не видит,
      // поэтому согласованность проверяется здесь.
      final icon = ColumnLayout.defaults.find(FsColumn.icon)!;
      expect(icon.width, closeTo(metrics.iconColumnWidth, 1));
      expect(icon.minWidth, icon.width);
    });

    test('обводка остаётся в одну точку', () {
      // Единственное значение не по коэффициенту: иначе линия размылась бы.
      expect(metrics.strokeWidth, 1);
    });
  });
}
