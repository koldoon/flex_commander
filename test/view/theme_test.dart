import 'package:flex_commander/model/panel/column_spec.dart';
import 'package:flex_commander/view/theme/app_colors.dart';
import 'package:flex_commander/view/theme/app_metrics.dart';
import 'package:flex_commander/view/theme/app_theme.dart';
import 'package:flex_commander/view/theme/fc_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оформление взято у референсного приложения. Здесь закреплено то, что при
/// правках легко потерять молча: палитра, шрифты и кегль.
void main() {
  const colors = FcColors();

  test('тема одна', () {
    // Светлой темы нет: приложение выглядит так же, как референсное.
    expect(AppTheme.theme.brightness, Brightness.dark);
    expect(AppTheme.theme.extension<FcTheme>(), isNotNull);
  });

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
    const theme = FcTheme();

    test('интерфейс набран Ubuntu, список файлов — Consolas', () {
      expect(theme.uiStyle.fontFamily, 'Ubuntu');
      expect(theme.rowStyle.fontFamily, 'Consolas');
      expect(theme.headerStyle.fontFamily, 'Ubuntu');
      expect(theme.buttonStyle.fontFamily, 'Ubuntu');
    });

    test('кегль один на всё приложение: `h5` референса', () {
      const expected = 34 * FcMetrics.fontScale;
      expect(theme.metrics.fontSize, expected);
      for (final style in [theme.uiStyle, theme.rowStyle, theme.headerStyle, theme.pathStyle, theme.buttonStyle]) {
        expect(style.fontSize, expected);
      }
    });

    test('иконки — глифы FontAwesome', () {
      expect(FcIcons.folder.fontFamily, 'FontAwesome');
      expect(FcIcons.folder.codePoint, 0xf07b);
      expect(FcIcons.link.codePoint, 0xf0c1);
      expect(FcIcons.asterisk.codePoint, 0xf069);
      expect(FcIcons.caretUp.codePoint, 0xf0d8);
      expect(FcIcons.caretDown.codePoint, 0xf0d7);
    });
  });

  group('размеры', () {
    const metrics = FcMetrics();

    test('выведены из исходников референса одним коэффициентом', () {
      // `height="50"` у строки, `height="60"` у плашки пути и кнопки.
      expect(metrics.rowHeight, 50 * FcMetrics.scale);
      expect(metrics.pathHeaderHeight, 60 * FcMetrics.scale);
      expect(metrics.buttonHeight, 60 * FcMetrics.scale);
    });

    test('кегль мельче, чем даёт коэффициент разметки', () {
      // Замер снимка работающего референса: текст там мельче, чем следует из
      // отношения 34 к 50 в исходниках. Геометрия при этом совпадает.
      expect(FcMetrics.fontScale, lessThan(FcMetrics.scale));
      expect(metrics.fontSize, lessThan(34 * FcMetrics.scale));
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
