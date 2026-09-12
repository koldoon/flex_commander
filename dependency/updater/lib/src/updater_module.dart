import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:path/path.dart' as p;

import 'channel_app_build.dart';
import 'github_releases.dart';
import 'update_commands.dart';
import 'update_service.dart';
import 'updater_settings.dart';

/// Приложение обновляет себя само.
///
/// Выключишь — приложение перестанет знать о новых сборках, но соберётся и
/// будет работать; ставить выпуск придётся руками, как и раньше
/// (`docs/spec/self-update.md`).
///
/// Половина одна, экранная: в сеть ходит она же. Через границу тут ничего не
/// ездит — обновляется само приложение, а не то, что оно показывает.
class Updates implements FcFrontendModule {
  const Updates({this.repository = defaultRepository});

  static const String commandId = 'fc.updater';

  /// Откуда брать выпуски. Тот же репозиторий, из которого собрано приложение.
  static const String defaultRepository = 'koldoon/flex_commander';

  final String repository;

  @override
  String get id => commandId;

  @override
  String get title => 'Updates';

  @override
  void installFrontend(FrontendRegistry registry) {
    final settings = registry.settings;
    UpdaterSettings settingsOf() => settings.section(UpdaterSettings.new);

    final build = ChannelAppBuild();
    UpdateService? service;
    UpdateService updates() =>
        service ??= UpdateService(
          build: build,
          source: GithubReleases(repository: repository),
          processes: () => registry.services.resolve<ProcessRunner>(),
          settings: settingsOf,
          save: settings.save,
          // Рядом с настройками, а не в системном кеше: у приложения уже есть
          // свой каталог, и класть скачанное туда же понятнее — видно, что
          // это наше и что это можно снести.
          cache: Directory(p.join(_home, '.flex-commander', 'updates')),
        );

    registry.command((context) => CheckForUpdatesCommand(updates: updates));

    // При запуске: спросить раннера о себе, убрать отложенную сборку и, если
    // пора, сходить на GitHub.
    registry.startup((context) => _PrepareUpdatesCommand(build: build, updates: updates));

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'checkAtStartup',
          defaultValue: true,
          title: strings.tr('Check for updates'),
          description: strings.tr('Ask GitHub at startup, once a day'),
          read: () => settingsOf().checkAtStartup,
          write: (value) => settingsOf().checkAtStartup = value,
          // Кнопка живая и при снятом флажке: отказ проверять по расписанию не
          // значит отказа проверить сейчас.
          action: SettingsAction(
            label: strings.tr('Check now'),
            run: () => unawaited(runUpdate(registry.services.resolve<Application>(), updates(), byHand: true)),
          ),
        ),
      ], save: settings.save);
    });

    registry.strings('ru', _russian);
  }

  static String get _home =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path;
}

/// Стартовая работа модуля: узнать о себе и, если пора, спросить о новом.
class _PrepareUpdatesCommand extends AppCommand {
  _PrepareUpdatesCommand({required this.build, required this.updates});

  final ChannelAppBuild build;
  final UpdateService Function() updates;

  @override
  String get id => 'app.checkForUpdates.startup';

  @override
  String get label => tr('Check for updates at startup');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    // Сведения о себе спрашиваются здесь, а не при сборке модуля: канал раннера
    // к тому времени ещё не готов.
    await build.load();

    // Сборка, не знающая своей версии, обновляться не умеет: канала раннера
    // нет — значит нет и бандла. Так живут проверки и `flutter run`, и ходить
    // за них в сеть незачем — ни запроса, ни таймера.
    if (build.version == null || build.bundlePath.isEmpty) {
      return;
    }

    await CheckForUpdatesAtStartupCommand(updates: updates).execute(context);
  }
}

const Map<String, String> _russian = {
  'Updates': 'Обновления',
  'Check for updates': 'Проверять обновления',
  'Ask GitHub at startup, once a day': 'Спрашивать GitHub при запуске, не чаще раза в сутки',
  'Check now': 'Проверить сейчас',
  'Check for updates at startup': 'Проверка обновлений при запуске',
  'Ask GitHub whether a newer build is out': 'Спросить GitHub, нет ли сборки новее',
  'You are up to date': 'У вас и так свежее',
  'Downloading {version}': 'Загрузка {version}',
  'Version {version} is ready': 'Версия {version} готова',
  'No release notes': 'Заметок к выпуску нет',
  'Later': 'Позже',
  'Restart': 'Перезапустить',
  'Could not install the update': 'Поставить обновление не вышло',
  'This build does not know its own version': 'Эта сборка не знает своей версии',
  'No releases published yet': 'Выпусков пока нет',
  'No build for this processor': 'Сборки под этот процессор нет',
  'The release has no checksum to verify': 'У выпуска нет суммы для проверки',
  'Cannot write to the application folder': 'В каталог приложения нельзя писать',
};
