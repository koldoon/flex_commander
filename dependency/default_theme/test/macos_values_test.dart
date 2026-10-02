import 'dart:math' as math;

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Отношение контраста по WCAG: во сколько раз одно светлее другого.
///
/// Прозрачность учитывается сложением поверх фона, а не отбрасыванием: почти все
/// подписи macOS заданы чёрным или белым с альфой, и без сложения числа вышли бы
/// не те.
double _contrast(Color foreground, Color background, {Color? under}) {
  final bg = under == null ? background : Color.alphaBlend(background, under);
  final fg = Color.alphaBlend(foreground, bg);
  final light = math.max(fg.computeLuminance(), bg.computeLuminance());
  final dark = math.min(fg.computeLuminance(), bg.computeLuminance());
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  const light = MacOsColors(tones: macOsLightTones);
  const dark = MacOsColors(tones: macOsDarkTones);

  group('палитра снята с системы, а не подобрана', () {
    test('подписи — иерархия labelColor', () {
      // `NSColor.labelColor` и `secondaryLabelColor`, macOS 27, обе внешности.
      expect(light.rowText, const Color(0xD8000000));
      expect(dark.rowText, const Color(0xD8FFFFFF));
      expect(light.secondaryText, const Color(0x7F000000));
      expect(dark.secondaryText, const Color(0x8CFFFFFF));
    });

    test('подложка и содержимое разведены, хотя система их свела', () {
      // В macOS 27 `windowBackgroundColor` и `controlBackgroundColor` совпали, и
      // панель на таком фоне пропала бы. Взят `underPageBackgroundColor`.
      expect(light.windowBackground, const Color(0xFFF6F6F6));
      expect(light.panelBackground, const Color(0xFFFFFFFF));
      expect(dark.windowBackground, const Color(0xFF282828));
      expect(dark.panelBackground, const Color(0xFF1E1E1E));

      // Порознь — в каждой внешности своя сторона, но всегда порознь.
      expect(light.windowBackground, isNot(light.panelBackground));
      expect(dark.windowBackground, isNot(dark.panelBackground));
    });

    test('карточка приподнята над обеими поверхностями, на каких стоит', () {
      // Карточка раздела встаёт и в окне команды, и прямо на панели: сведения
      // об объекте показываются полноэкранным просмотром. Сплошной цвет
      // совпал бы с одной из двух — на живом приложении так и вышло, карточка
      // в сведениях пропала.
      // Требуется различимый перепад, а не просто «не совпало»: на светлой
      // внешности у карточки нет обводки, и держит её только тон. Разница в
      // один-два уровня прошла бы проверку на неравенство и пропала бы на
      // экране.
      for (final colors in [light, dark]) {
        for (final under in [colors.panelBackground, colors.dialogBackground]) {
          final over = Color.alphaBlend(colors.dialogListBackground, under);
          expect(
            _contrast(over, under),
            greaterThanOrEqualTo(1.04),
            reason: 'карточка неразличима на том, на чём лежит',
          );
        }
      }
    });

    test('тень на светлой слабее, чем на тёмной', () {
      // Одинаковый вес не годится: на тёмном фоне тень почти не видна и нужна
      // в полную силу, а на светлом четверть чёрного с размытием читается серым
      // ореолом и съедает край кнопки. Живьём это и вышло: белая кнопка на
      // светло-сером фоне выглядела мутной.
      expect(light.shadow.a, lessThan(dark.shadow.a / 2));
    });

    test('ни у кнопки, ни у карточки нет края и подъёма — только заливка', () {
      // Так выглядят современные поверхности macOS в обеих внешностях: плашка
      // на подложке, без обводки и без тени. Правило одно на светлую и тёмную.
      for (final colors in [light, dark]) {
        expect(colors.controlShadow.a, 0);
        expect(colors.buttonBorder.a, 0);
        expect(colors.dialogListBorder.a, 0);
      }
    });

    test('на тёмной у панели нет обводки, и её держит заливка', () {
      // Края нет — значит панель обязана отличаться от подложки сама. На
      // светлой обводка пока оставлена: там перепад меньше, и убирать её без
      // живой проверки значило бы гадать.
      expect(dark.panelBorder.a, 0);
      expect(
        _contrast(dark.panelBackground, dark.windowBackground),
        greaterThanOrEqualTo(1.04),
        reason: 'без обводки панель сливается с подложкой',
      );
      expect(light.panelBorder.a, greaterThan(0));
    });

    test('кнопка различима на карточке, на которой лежит', () {
      // Следствие предыдущего: раз края нет, всё держит заливка. Кнопка стоит
      // внутри карточки раздела, а та — на фоне окна команды.
      for (final colors in [light, dark]) {
        final card = Color.alphaBlend(colors.dialogListBackground, colors.dialogBackground);
        final button = Color.alphaBlend(colors.buttonBackground, card);
        expect(_contrast(button, card), greaterThanOrEqualTo(1.1), reason: 'кнопка сливается с карточкой');
      }
    });

    test('активная плашка отличается от пассивной, и заметно', () {
      // Живьём они были неразличимы: `unemphasizedSelection` и `controlColor` на
      // тёмной внешности сходятся почти в один тон, а поверх фона окна пассивная
      // выходила даже светлее активной. Оттенками серого это не развести —
      // активная взята акцентом, как выбранный сегмент переключателя macOS.
      for (final colors in [light, dark]) {
        final active = Color.alphaBlend(colors.pathBackground, colors.windowBackground);
        final passive = Color.alphaBlend(colors.pathInactiveBackground, colors.windowBackground);
        expect(_contrast(active, passive), greaterThanOrEqualTo(1.5), reason: 'плашки панелей не различить');
      }
    });

    test('разделитель светлее того, что делит, а не темнее', () {
      // `gridColor` на тёмной внешности `#1A1A1A` — темнее и панели, и
      // карточки: линия ушла бы в тень вместо того, чтобы делить. Поэтому
      // разделитель взят `separatorColor`.
      final card = Color.alphaBlend(dark.dialogListBackground, dark.dialogBackground);
      final divider = Color.alphaBlend(dark.columnDivider, card);
      expect(divider.computeLuminance(), greaterThan(card.computeLuminance()));
    });

    test('шестнадцать цветов ANSI — из профилей Terminal.app', () {
      expect(light.terminalAnsi, hasLength(16));
      expect(dark.terminalAnsi, hasLength(16));

      // `Clear Light`: цвет 0 и цвет 15 по краям набора.
      expect(light.terminalAnsi.first, const Color(0xFF2D3840));
      expect(light.terminalAnsi.last, const Color(0xFFD8E1E7));
      // `Clear Dark`.
      expect(dark.terminalAnsi.first, const Color(0xFF35424C));
      expect(dark.terminalAnsi.last, const Color(0xFFE5EFF5));

      // Наборы разные: набор под тёмный фон на светлом нечитаем, и наоборот.
      expect(light.terminalAnsi, isNot(dark.terminalAnsi));
    });

    test('подсветка — из тем Xcode, приведённая к sRGB', () {
      // `xcode.syntax.keyword` темы «Default (Light)». Без приведения из
      // калибровочного RGB вышел бы `#9B2393` — и разошёлся бы с Xcode.
      expect(light.syntaxKeyword, const Color(0xFFAD3DA4));
      expect(light.syntaxString, const Color(0xFFD12F1B));
      expect(dark.syntaxKeyword, const Color(0xFFFF7AB2));
      expect(dark.syntaxString, const Color(0xFFFF8170));
    });

    test('пометка оранжевая, а не акцентная', () {
      // Курсор акцентный; будь пометка тоже акцентной, помеченная строка под
      // курсором стала бы неотличимой.
      expect(light.markedBar, const Color(0xFFFF8D28));
      expect(dark.markedBar, const Color(0xFFFF9230));
      expect(light.markedBar, isNot(light.cursorBackground));
    });
  });

  group('акцент', () {
    test('без службы — синий системный', () {
      expect(light.cursorBackground, macOsBlueAccent);
      expect(light.buttonPrimaryBackground, macOsBlueAccent);
      expect(light.progress, macOsBlueAccent);
      expect(light.focusRing.withValues(alpha: 1), macOsBlueAccent);
    });

    test('ведёт ровно те роли, которые красит система', () {
      const pink = Color(0xFFFF2D55);
      const withPink = MacOsColors(tones: macOsLightTones, accent: pink);

      expect(withPink.cursorBackground, pink);
      expect(withPink.buttonPrimaryBackground, pink);
      expect(withPink.progress, pink);
      expect(withPink.pathBackground, pink);
      expect(withPink.focusRing, pink.withValues(alpha: 0.5));
      expect(withPink.inputSelection, pink.withValues(alpha: 0.3));

      // А неакцентные роли смена акцента не шевелит.
      expect(withPink.rowText, light.rowText);
      expect(withPink.panelBackground, light.panelBackground);
      expect(withPink.markedBar, light.markedBar);
    });

    test('подпись на акценте — белая, но не когда акцент светлее её', () {
      // Все восемь системных акцентов достаточно темны, и система всегда даёт
      // белый. «Другой…» в настройках даёт любой цвет — вплоть до почти белого,
      // на котором белое исчезает.
      for (final accent in [
        const Color(0xFF007AFF), // Blue
        const Color(0xFFFF2D55), // Pink
        const Color(0xFFAF52DE), // Purple
        const Color(0xFFFF9500), // Orange
        const Color(0xFF28CD41), // Green
        const Color(0xFF8E8E93), // Graphite
      ]) {
        expect(
          MacOsColors(tones: macOsLightTones, accent: accent).cursorText,
          const Color(0xFFFFFFFF),
          reason: 'на системном акценте подпись белая',
        );
      }

      const almostWhite = Color(0xFFFFF7C0);
      expect(
        MacOsColors(tones: macOsLightTones, accent: almostWhite).cursorText,
        macOsLightTones.label,
        reason: 'на светлом акценте белая подпись исчезла бы',
      );
    });
  });

  group('контраст: читается ли то, что написано', () {
    // Порог для основного текста — 4.5, для второстепенного и для подписи на
    // акценте — 3. Почему у акцента меньше: белое на `#007AFF` даёт 4.05, и это
    // сочетание самой Apple. Требовать больше значило бы не пользоваться
    // системным акцентом вовсе.
    for (final (name, colors) in [('светлое', light), ('тёмное', dark)]) {
      test('$name оформление: основной текст различим', () {
        expect(_contrast(colors.rowText, colors.panelBackground), greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.headerText, colors.panelBackground), greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.inputText, colors.inputBackground), greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.dialogLabel, colors.dialogBackground), greaterThanOrEqualTo(4.5));
        expect(
          _contrast(colors.buttonText, colors.buttonBackground, under: colors.dialogBackground),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.functionButtonText, colors.functionButtonBackground, under: colors.windowBackground),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('$name оформление: второстепенный текст и подписи на акценте', () {
        expect(_contrast(colors.secondaryText, colors.panelBackground), greaterThanOrEqualTo(3));
        expect(_contrast(colors.sizeText, colors.panelBackground), greaterThanOrEqualTo(3));
        expect(_contrast(colors.inputHint, colors.inputBackground), greaterThanOrEqualTo(3));
        expect(_contrast(colors.dialogText, colors.dialogBackground), greaterThanOrEqualTo(3));
        expect(
          _contrast(colors.functionKeyNumber, colors.functionButtonBackground, under: colors.windowBackground),
          greaterThanOrEqualTo(3),
        );
        expect(
          _contrast(colors.pathInactiveText, colors.pathInactiveBackground, under: colors.windowBackground),
          greaterThanOrEqualTo(3),
        );
        expect(_contrast(colors.cursorText, colors.cursorBackground), greaterThanOrEqualTo(3));
        expect(_contrast(colors.pathText, colors.pathBackground), greaterThanOrEqualTo(3));
        // Крошки приглушены, но читаемы: приглушать надо то, чем пишут по
        // плашке, а не подпись списка файлов — иначе на акцентной заливке
        // выходит чёрным по синему.
        expect(_contrast(colors.pathSecondaryText, colors.pathBackground), greaterThanOrEqualTo(2));
        expect(
          colors.pathSecondaryText.computeLuminance() > colors.pathBackground.computeLuminance(),
          colors.pathText.computeLuminance() > colors.pathBackground.computeLuminance(),
          reason: 'крошки и текущий каталог должны быть с одной стороны от заливки',
        );
        expect(_contrast(colors.buttonPrimaryText, colors.buttonPrimaryBackground), greaterThanOrEqualTo(3));
      });

      test('$name оформление: курсор и пометка не сливаются со строкой', () {
        // Помеченная строка под курсором — не выдуманный случай: `Ins` ведёт
        // курсор по помеченным.
        expect(_contrast(colors.cursorBackground, colors.panelBackground), greaterThanOrEqualTo(1.5));
        expect(_contrast(colors.markedBar, colors.cursorBackground), greaterThanOrEqualTo(1.5));
      });
    }
  });

  group('список файлов набран Ubuntu, без поправок строки', () {
    // `docs/spec/macos-themes.md`, §2а: поправки замерены на Consolas.
    final themes = [
      macOsLightTheme(),
      macOsDarkTheme(),
      macOsAutoTheme(brightness: Brightness.light),
      macOsAutoTheme(brightness: Brightness.dark),
    ];

    test('шрифт списка — Ubuntu, моноширинный остаётся', () {
      for (final theme in themes) {
        expect(theme.fonts.list, 'Ubuntu', reason: theme.id);
        expect(theme.fonts.fixed, const DefaultFonts().fixed, reason: theme.id);
        expect(theme.fonts.ui, const DefaultFonts().ui, reason: theme.id);
      }
    });

    test('поправки строки обнулены, прочие размеры референсные', () {
      for (final theme in themes) {
        expect(theme.metrics.rowTextVerticalNudge, 0, reason: theme.id);
        expect(theme.metrics.rowContentVerticalNudge, 0, reason: theme.id);
        expect(theme.metrics.rowHeight, const DefaultMetrics().rowHeight, reason: theme.id);
      }
    });

    test('референсная тема не тронута', () {
      expect(const DefaultFonts().list, const DefaultFonts().fixed);
      expect(const DefaultMetrics().rowTextVerticalNudge, isNot(0));
    });
  });
}
