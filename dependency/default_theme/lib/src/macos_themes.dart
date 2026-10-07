import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'default_fonts.dart';
import 'default_icons.dart';
import 'default_metrics.dart';
import 'macos_colors.dart';
import 'macos_palette.dart';

/// Имена, под которыми оформления попадают в настройки.
///
/// С точкой — и это защита, а не украшение. Своё оформление человек складывает в
/// редакторе, и `id` ему выводится из названия заменой всего, что не буква и не
/// цифра, на дефис: точку такое правило произвести не может **никогда**.
/// А `registry.theme` дубли по `id` не ловит, и накладка редактора выкладывается
/// стартовой командой **после** сборки — то есть тема человека под названием
/// «Light» молча вытеснила бы встроенную, будь та названа `light`.
abstract final class MacOsThemeIds {
  static const String light = 'fc.light';
  static const String dark = 'fc.dark';

  /// «Вслед за оформлением macOS» — не цвет, а правило.
  ///
  /// Стоит в том же списке, что и темы, и это не уловка: правило принадлежит
  /// **группе оформлений своей системы**, а не оформлению вообще. Светлое и
  /// тёмное macOS приходят парой и умеют меняться по системе; появится порт на
  /// Windows — его модуль принесёт свою пару и своё «вслед за оформлением
  /// Windows», не трогая ни общих настроек, ни этой.
  ///
  /// Поэтому отдельного поля правила в настройках нет: выбор один, и он там же,
  /// где был.
  static const String auto = 'fc.auto';
}

/// Размеры оформлений macOS: референсные, кроме поправок строки списка.
///
/// Обе поправки замерены на Consolas, а список здесь набран Ubuntu
/// ([MacOsFonts]): под ним они только опускают текст ниже середины строки
/// (`docs/spec/macos-themes.md`, §2а).
class MacOsMetrics extends DefaultMetrics {
  const MacOsMetrics();

  @override
  double get rowContentVerticalNudge => 0;

  @override
  double get rowTextVerticalNudge => 0;
}

/// Шрифты оформлений macOS: референсные, но список файлов набран Ubuntu, как и
/// интерфейс. Моноширинный — для кода, терминала и просмотра — остаётся.
class MacOsFonts extends DefaultFonts {
  const MacOsFonts();

  @override
  String get list => 'Ubuntu';
}

/// Светлое оформление по цветам macOS.
///
/// Иконки — общие с референсным, размеры и шрифты — почти: гайдлайны Apple
/// здесь про цвет, а раскладка у приложения своя. Глифы красятся ролью цвета,
/// поэтому переезжают сами.
FcThemeSpec macOsLightTheme({SystemAccentColors? accent}) => FcThemeSpec(
  id: MacOsThemeIds.light,
  title: 'macOS Light',
  brightness: Brightness.light,
  colors: MacOsColors(tones: macOsLightTones, accent: accent),
  metrics: const MacOsMetrics(),
  icons: const DefaultIcons(),
  fonts: const MacOsFonts(),
);

/// Тёмное оформление по цветам macOS.
///
/// `brightness` здесь совпадает с умолчанием конструктора, но назван всё равно:
/// у светлой его забыть нельзя, и пара, в которой одна половина говорит, а
/// другая молчит, читается как недосмотр.
FcThemeSpec macOsDarkTheme({SystemAccentColors? accent}) => FcThemeSpec(
  id: MacOsThemeIds.dark,
  title: 'macOS Dark',
  brightness: Brightness.dark,
  colors: MacOsColors(tones: macOsDarkTones, accent: accent),
  metrics: const MacOsMetrics(),
  icons: const DefaultIcons(),
  fonts: const MacOsFonts(),
);

/// Оформление, идущее за внешним видом системы.
///
/// Снаружи это обычная тема: служба оформлений списочная, и правило,
/// предъявленное темой, не требует от неё ни нового поля, ни нового понятия.
/// Внутри — та же пара тонов, выбранная по яркости, которую сообщил Flutter.
/// Сменился внешний вид системы — модуль перевыкладывает эту тему с другой
/// половиной пары, и приложение перекрашивается тем же порядком, каким оно
/// перекрашивается от смены акцента.
FcThemeSpec macOsAutoTheme({required Brightness brightness, SystemAccentColors? accent}) => FcThemeSpec(
  id: MacOsThemeIds.auto,
  title: 'Follow macOS theme',
  brightness: brightness,
  colors: MacOsColors(tones: brightness == Brightness.light ? macOsLightTones : macOsDarkTones, accent: accent),
  metrics: const MacOsMetrics(),
  icons: const DefaultIcons(),
  fonts: const MacOsFonts(),
);
