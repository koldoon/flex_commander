import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_theme_editor/fc_theme_editor.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_commander/view/theme/app_theme.dart';

/// Роли, которым позволено совпасть с референсной темой, — и почему каждой.
///
/// Совпадение значения само по себе не ошибка: белое — оно и есть белое, и если
/// верный ответ у двух оформлений один, расходиться им незачем. Ошибка — это
/// роль, о которой **забыли**, и от забытой она отличается тем, что здесь
/// названа с причиной. Всё, что совпало без причины, тест покажет.
const Map<String, String> _sameAsReference = {
  // Чёрный 45 % замерен с собственного значка macOS, то есть уже системный:
  // менять его незачем (`docs/spec/file-thumbnails.md`, §9).
  'iconShadow': 'замер системного значка',
  // Подпись поверх заливки выделения: и там и здесь белая. У референса потому,
  // что выделение тёмно-синее; у нас потому, что так отвечает сама система
  // (`alternateSelectedControlTextColor`).
  'cursorText': 'белая подпись на заливке выделения',
  'iconSelected': 'белая подпись на заливке выделения',
  'buttonPrimaryText': 'белая подпись на акценте',
  // Плашка активной панели стала акцентной, и подпись на ней — белой. У
  // референса плашка тёмно-синяя, и подпись тоже белая: заливки разные, ответ
  // один.
  'pathText': 'белая подпись на заливке плашки',
  // `headerTextColor` тёмной внешности и `textColor` — чистый белый, и он же
  // стоит у референса. Разными их сделало бы только желание отличаться.
  'headerText': 'чистый белый в обеих внешностях',
  'inputText': 'чистый белый в тёмной внешности',
};

void main() {
  const light = MacOsColors(tones: macOsLightTones);
  const dark = MacOsColors(tones: macOsDarkTones);
  const reference = DefaultColors();

  group('полнота: ни одна роль не досталась от референса по недосмотру', () {
    // Отображение наследуется от контракта, а не от `DefaultColors`, — забытую
    // обязательную роль требует компилятор. Но четыре роли объявлены с
    // умолчанием (`dialogListBackground`, `dialogListBorder`, `focusRing`,
    // `iconShadow`), и их забыть можно молча: они остались бы тёмно-синими
    // посреди светлого окна. Сторожем — этот тест, и ходит он по каталогу
    // редактора, то есть по всем ролям, какие есть.
    for (final (name, colors) in [('светлого', light), ('тёмного', dark)]) {
      test('у $name оформления назван весь набор', () {
        final inherited = <String>[];
        for (final role in colorRoles) {
          if (_sameAsReference.containsKey(role.name)) {
            continue;
          }
          if (role.read(colors) == role.read(reference)) {
            inherited.add(role.name);
          }
        }
        expect(inherited, isEmpty, reason: 'роли достались от референсной темы, а должны быть свои');
      });
    }

    test('каталог знает столько ролей, сколько их в контракте', () {
      // Пятьдесят семь: пятьдесят шесть цветов и шестнадцать ANSI, разложенные
      // по номерам. Число сторожит доктринальный тест редактора; здесь — что
      // каталог вообще непуст и обходится.
      expect(colorRoles.length, greaterThan(50));
    });
  });

  group('оформления доезжают до дерева виджетов', () {
    test('яркость уходит в ThemeData, а не остаётся в спеке', () {
      expect(buildThemeData(macOsLightTheme()).brightness, Brightness.light);
      expect(buildThemeData(macOsDarkTheme()).brightness, Brightness.dark);
    });

    test('фон окна у трёх оформлений разный', () {
      final backgrounds = {
        buildThemeData(macOsLightTheme()).scaffoldBackgroundColor,
        buildThemeData(macOsDarkTheme()).scaffoldBackgroundColor,
        const Color(0xFF011130), // референсное: `FcPalette.blue3`
      };
      expect(backgrounds, hasLength(3), reason: 'два оформления с одним фоном — это одно оформление');
    });

    test('подпись кнопки подтверждения своя, а не общая с обычной', () {
      // Своя роль появилась ради светлого оформления: обычная кнопка белая,
      // подтверждающая залита акцентом, и одной подписью их не покрыть.
      final theme = macOsLightTheme().theme;
      expect(theme.buttonPrimaryStyle.color, isNot(theme.buttonStyle.color));

      // А у референсной темы роль с умолчанием, и подпись осталась одна.
      const spec = FcThemeSpec(
        id: 'reference',
        title: 'Reference',
        colors: DefaultColors(),
        metrics: DefaultMetrics(),
        icons: DefaultIcons(),
        fonts: DefaultFonts(),
      );
      expect(spec.theme.buttonPrimaryStyle.color, spec.theme.buttonStyle.color);
    });
  });
}
