import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

import 'macos_themes.dart';
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
  String get label => tr('Switch theme');

  @override
  String get description => tr('Choose the application appearance');

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
  String get label => tr('Restore theme');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    // Незнакомое имя служба игнорирует: модуль темы могли отключить между
    // запусками, и это не повод не открыться.
    env.app.theme.use(settings.section(ThemeSettings.new).themeId);
  }
}

/// Держит оформления macOS в согласии с акцентом системы.
///
/// Перевыкладывает их **модуль тем**, а не модуль акцента, и это не мелочь:
/// иначе платформенный модуль знал бы про две конкретные темы — зависимость
/// наизнанку. Акцент он только приносит, а что им красить, решает тот, чьи темы.
class FollowAccentCommand extends AppCommand {
  FollowAccentCommand(this.env);

  final FcContext env;

  static const String commandId = 'app.theme.follow_accent';

  SystemAccent? _accent;
  Color? _light;
  Color? _dark;

  @override
  String get id => commandId;

  @override
  String get label => tr('Follow system accent');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    // Службы может не быть вовсе: канала нет на другой платформе и в тестах, а
    // модуль акцента можно выключить. `resolveAll` для этого и годится —
    // `resolve` бросил бы.
    final accent = env.resolveAll<SystemAccent>().firstOrNull;
    if (accent == null) {
      return;
    }
    _accent = accent;
    accent.addListener(_repaint);

    // И сразу: стартовые команды идут в порядке объявления модулей, а модуль
    // акцента объявлен позже темы — то есть к этому мгновению он ещё не
    // спрашивал. Но порядок модулей — не то, на что стоит опираться, и если
    // ответ уже приехал, он не должен пропасть.
    _repaint();
  }

  void _repaint() {
    final accent = _accent;
    if (accent == null || (accent.light == _light && accent.dark == _dark)) {
      return;
    }
    _light = accent.light;
    _dark = accent.dark;
    // `register` заменяет тему по имени **на том же месте списка**: порядок не
    // съедет, а выбор человека и не при чём — он хранится именем.
    env.app.theme.register(macOsLightTheme(accent: _light));
    env.app.theme.register(macOsDarkTheme(accent: _dark));
  }
}
