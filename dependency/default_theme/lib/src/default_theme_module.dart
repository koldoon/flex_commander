import 'package:fc_ui_api/fc_ui_api.dart';

import 'default_colors.dart';
import 'default_fonts.dart';
import 'default_icons.dart';
import 'default_metrics.dart';
import 'theme_commands.dart';

/// Оформление по умолчанию — то, с которым приложение выглядит как референс.
///
/// Здесь и живут все значения оформления: палитра референса, размеры,
/// выведенные из его же чисел, глифы и шрифты. API их не знает — он описывает
/// только роли, — поэтому вторая тема наследуется от [DefaultColors] и
/// переопределяет нужное, а не переписывает всё заново.
class DefaultTheme implements FcModule {
  const DefaultTheme();

  /// Имя темы: под ним она попадает в настройки.
  static const String themeId = 'default';

  static const String commandId = 'fc.default_theme';

  @override
  String get id => commandId;

  @override
  String get title => 'Default theme';

  @override
  void install(FcRegistry registry) {
    registry.theme(
      const FcThemeSpec(
        id: themeId,
        title: 'Default',
        colors: DefaultColors(),
        metrics: DefaultMetrics(),
        icons: DefaultIcons(),
        fonts: DefaultFonts(),
      ),
    );

    final settings = registry.settings;
    registry.command((context) => SwitchThemeCommand(context, settings));
    registry.startup((context) => RestoreThemeCommand(context, settings));
  }
}
