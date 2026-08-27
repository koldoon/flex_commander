import 'package:fc_api/fc_api.dart';

import 'theme_settings.dart';

/// Выбрать тему.
///
/// Действие, а не переключатель в настройках: тему меняют из списка команд, из
/// меню, когда-нибудь — горячей клавишей, и все эти способы должны делать
/// ровно одно и то же.
class SwitchThemeCommand extends AppCommand {
  SwitchThemeCommand(this.env, this.settings);

  /// Имя темы приходит параметром: одна команда на все темы, а не по команде
  /// на каждую.
  static const String themeIdParam = 'themeId';

  final FcContext env;
  final SettingsScope settings;

  static const String commandId = 'app.theme.use';

  @override
  String get id => commandId;

  @override
  String get label => 'Switch theme';

  @override
  String get description => 'Choose the application appearance';

  /// «Тёмная тема» ищется словом `dark`, а не словом `switch`.
  @override
  Set<String> get keywords => const {'dark', 'light', 'appearance', 'colors', 'look'};

  @override
  bool isExecutable(CommandContext context) => context.app.theme.available.length > 1;

  @override
  Future<void> execute(CommandContext context) async {
    final themeId = context.invocation.param<String>(themeIdParam) ?? _nextTheme();
    env.app.theme.use(themeId);

    // Выбор переживает перезапуск: тема — это то, что настраивают один раз.
    settings.section(ThemeSettings.new).themeId = env.app.theme.current.id;
    settings.save();
  }

  /// Следующая по кругу — так команда работает и без параметра.
  String _nextTheme() {
    final themes = env.app.theme.available;
    final current = themes.indexWhere((theme) => theme.id == env.app.theme.current.id);
    return themes[(current + 1) % themes.length].id;
  }
}

/// Восстанавливает выбранную тему при запуске.
///
/// Стартовая команда, а не чтение в `install`: настройки к моменту запуска уже
/// прочитаны, а до него их ещё нет.
class RestoreThemeCommand extends AppCommand {
  RestoreThemeCommand(this.env, this.settings);

  final FcContext env;
  final SettingsScope settings;

  static const String commandId = 'app.theme.restore';

  @override
  String get id => commandId;

  @override
  String get label => 'Restore theme';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    // Незнакомое имя служба игнорирует: модуль темы могли отключить между
    // запусками, и это не повод не открыться.
    env.app.theme.use(settings.section(ThemeSettings.new).themeId);
  }
}
