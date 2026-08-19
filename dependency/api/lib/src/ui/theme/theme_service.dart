import 'package:flutter/foundation.dart';

import 'app_colors.dart';
import 'app_metrics.dart';
import 'fc_fonts.dart';
import 'fc_icons.dart';
import 'fc_theme.dart';

/// Оформление, которое предлагает модуль.
///
/// Тема — это набор значений плюс имя, под которым её выбирают: имя попадает
/// в настройки, поэтому оно должно пережить и перезапуск, и отключение самого
/// модуля темы.
class FcThemeSpec {
  const FcThemeSpec({
    required this.id,
    required this.title,
    required this.colors,
    required this.metrics,
    required this.icons,
    required this.fonts,
    this.brightness = Brightness.dark,
  });

  /// Устойчивое имя для настроек: `default`, `light`, `solarized`.
  final String id;

  /// Название для пользователя.
  final String title;

  /// Светлая тема или тёмная — это нужно системным элементам вокруг окна.
  final Brightness brightness;

  final FcColors colors;
  final FcMetrics metrics;
  final FcIcons icons;
  final FcFonts fonts;

  /// Значения темы в виде расширения, которое виджеты достают через
  /// [FcTheme.of].
  FcTheme get theme => FcTheme(colors: colors, metrics: metrics, icons: icons, fonts: fonts);
}

/// Оформление приложения: какое есть и какое выбрано.
///
/// Переключение — обычное изменение состояния: служба уведомляет, приложение
/// пересобирает тему. Модуль темы ставит свою через [register] и переключается
/// на неё стартовой командой.
abstract interface class ThemeService implements Listenable {
  /// Все известные темы в порядке установки.
  List<FcThemeSpec> get available;

  /// Выбранная тема.
  ///
  /// Тема нужна всегда: без неё нечем красить. Приложение, в котором ни один
  /// модуль её не объявил, не собирается — так же, как без корневого источника
  /// дерева.
  FcThemeSpec get current;

  /// Ставит тему. Повторная установка с тем же [FcThemeSpec.id] заменяет
  /// прежнюю — так модуль обновляет своё оформление, не заводя второе имя.
  void register(FcThemeSpec spec);

  /// Выбирает тему по имени.
  ///
  /// Незнакомое имя игнорируется: в настройках могло остаться имя от модуля,
  /// который сейчас отключён, и запуск из-за этого падать не должен.
  void use(String id);
}
