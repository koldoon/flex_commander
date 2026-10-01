import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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

/// Светлое оформление по цветам macOS.
///
/// Размеры, иконки и шрифты — общие с референсным: гайдлайны Apple здесь про
/// цвет, а раскладка у приложения своя. Глифы красятся ролью цвета, поэтому
/// переезжают сами.
FcThemeSpec macOsLightTheme({Color? accent}) => FcThemeSpec(
  id: MacOsThemeIds.light,
  title: 'macOS Light',
  brightness: Brightness.light,
  colors: MacOsColors(tones: macOsLightTones, accent: accent),
  metrics: const DefaultMetrics(),
  icons: const DefaultIcons(),
  fonts: const DefaultFonts(),
);

/// Тёмное оформление по цветам macOS.
///
/// `brightness` здесь совпадает с умолчанием конструктора, но назван всё равно:
/// у светлой его забыть нельзя, и пара, в которой одна половина говорит, а
/// другая молчит, читается как недосмотр.
FcThemeSpec macOsDarkTheme({Color? accent}) => FcThemeSpec(
  id: MacOsThemeIds.dark,
  title: 'macOS Dark',
  brightness: Brightness.dark,
  colors: MacOsColors(tones: macOsDarkTones, accent: accent),
  metrics: const DefaultMetrics(),
  icons: const DefaultIcons(),
  fonts: const DefaultFonts(),
);

/// Оформление, идущее за внешним видом системы.
///
/// Снаружи это обычная тема: служба оформлений списочная, и правило,
/// предъявленное темой, не требует от неё ни нового поля, ни нового понятия.
/// Внутри — та же пара тонов, выбранная по яркости, которую сообщил Flutter.
/// Сменился внешний вид системы — модуль перевыкладывает эту тему с другой
/// половиной пары, и приложение перекрашивается тем же порядком, каким оно
/// перекрашивается от смены акцента.
FcThemeSpec macOsAutoTheme({required Brightness brightness, Color? accent}) => FcThemeSpec(
  id: MacOsThemeIds.auto,
  title: 'Follow macOS theme',
  brightness: brightness,
  colors: MacOsColors(tones: brightness == Brightness.light ? macOsLightTones : macOsDarkTones, accent: accent),
  metrics: const DefaultMetrics(),
  icons: const DefaultIcons(),
  fonts: const DefaultFonts(),
);
