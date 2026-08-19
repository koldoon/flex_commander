import 'package:fc_api/fc_api.dart';

import 'theme_commands.dart';

/// Оформление по умолчанию — то, с которым приложение выглядит как референс.
///
/// Модуль не выдумывает новых цветов: он объявляет темой то, что API считает
/// умолчанием. Смысл здесь не в палитре, а в том, что даже она подключается
/// как всё остальное — и рядом с ней встанет любая другая.
class DefaultTheme implements FcModule {
  const DefaultTheme();

  /// Имя темы: под ним она попадает в настройки.
  static const String themeId = 'default';

  @override
  String get id => 'fc.default_theme';

  @override
  String get title => 'Default theme';

  @override
  void install(FcRegistry registry) {
    registry.theme(const FcThemeSpec(id: themeId, title: 'Default'));

    final settings = registry.settings;
    registry.command((context) => SwitchThemeCommand(context, settings));
    registry.startup((context) => RestoreThemeCommand(context, settings));
  }
}
