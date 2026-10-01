import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

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

/// Держит оформления macOS в согласии с системой: акцент, яркость и рама окна.
///
/// Перевыкладывает их **модуль тем**, а не модуль акцента, и это не мелочь:
/// иначе платформенный модуль знал бы про конкретные темы — зависимость
/// наизнанку. Акцент он только приносит, а яркость приносит сам Flutter, и
/// канала для неё не нужно вовсе.
class FollowSystemAppearanceCommand extends AppCommand with WidgetsBindingObserver {
  FollowSystemAppearanceCommand(this.env);

  final FcContext env;

  static const String commandId = 'app.theme.follow_system';

  SystemAccent? _accent;
  Brightness? _brightness;

  @override
  String get id => commandId;

  @override
  String get label => tr('Follow system appearance');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    // Яркость спрашиваем у Flutter: это не платформенная вещь за каналом, а
    // то, что движок знает сам. Наблюдателем, а не заменой обработчика в
    // `PlatformDispatcher`: тот один на приложение, и второй желающий молча
    // отобрал бы его у первого.
    WidgetsBinding.instance.addObserver(this);
    _brightness = _systemBrightness;

    // Службы акцента может не быть вовсе: канала нет на другой платформе и в
    // тестах, а модуль можно выключить. `resolveAll` для этого и годится.
    final accent = env.resolveAll<SystemAccent>().firstOrNull;
    if (accent != null) {
      _accent = accent;
      accent.addListener(_repaint);
    }

    // Рама идёт за выбранным оформлением, каким бы оно ни было: это свойство
    // яркости, а не нашей пары.
    env.app.theme.addListener(_matchWindow);
    _matchWindow();

    _repaint();
  }

  @override
  void didChangePlatformBrightness() {
    final now = _systemBrightness;
    if (now == _brightness) {
      return;
    }
    _brightness = now;
    _repaint();
  }

  Brightness get _systemBrightness => WidgetsBinding.instance.platformDispatcher.platformBrightness;

  void _repaint() {
    final light = _accent?.light;
    final dark = _accent?.dark;
    final brightness = _brightness ?? Brightness.dark;

    // `register` заменяет тему по имени **на том же месте списка**: порядок не
    // съедет, а выбор человека хранится именем и не при чём.
    env.app.theme.register(macOsLightTheme(accent: light));
    env.app.theme.register(macOsDarkTheme(accent: dark));
    env.app.theme.register(
      macOsAutoTheme(brightness: brightness, accent: brightness == Brightness.light ? light : dark),
    );
  }

  /// Рама окна — по яркости выбранного оформления.
  void _matchWindow() {
    final service = env.resolveAll<WindowService>().firstOrNull;
    unawaited(service?.setBrightness(env.app.theme.current.brightness));
  }
}
