import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
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

    test('интерфейс набран Ubuntu, список файлов — системным Consolas', () {
      expect(theme.uiStyle.fontFamily, 'Ubuntu');
      expect(theme.rowStyle.fontFamily, 'Consolas');
      // Свой Consolas приложение не возит: где его нет, подставляется
      // моноширинный из системы, а не что придётся.
      expect(theme.rowStyle.fontFamilyFallback, ['Menlo']);
      expect(theme.headerStyle.fontFamily, 'Ubuntu');
      expect(theme.buttonStyle.fontFamily, 'Ubuntu');
    });

    test('кегль один на всё приложение: `h5` референса', () {
      const expected = 13.09;
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

    test('стоят числами, а не выводятся из коэффициента', () {
      // Пропорции референса сохранены — но проверяется теперь то, что человек
      // прочитает в наборе, а не то, что получится после умножения.
      // `height="50"` у строки, `height="60"` у плашки пути и кнопки.
      expect(metrics.rowHeight, 20);
      expect(metrics.pathHeaderHeight, 24);
      expect(metrics.buttonHeight, 24);
    });

    test('кегль мельче, чем даёт геометрия разметки', () {
      // Замер снимка работающего референса: текст там мельче, чем следует из
      // отношения 34 к 50 в исходниках. Геометрия при этом совпадает.
      //
      // Отношение 34/50 от высоты строки дало бы 13.6; замер дал 13.09.
      expect(metrics.fontSize, lessThan(metrics.rowHeight * 34 / 50));
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
