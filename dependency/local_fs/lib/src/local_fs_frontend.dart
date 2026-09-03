import 'package:fc_api/fc_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'local_fs_settings.dart';

/// Локальная файловая система — экранная половина: платформенное, что работает
/// только там, где есть окно.
///
/// Буфер обмена и окно — это платформенные каналы, а они живут в том изоляте,
/// который рисует. Раздел настроек тоже здесь: рисует его окно настроек.
class LocalFileSystemFrontend implements FcFrontendModule {
  const LocalFileSystemFrontend();

  @override
  String get id => 'fc.local_fs';

  @override
  String get title => 'Local file system';

  @override
  void installFrontend(FrontendRegistry registry) {
    final settings = registry.settings;

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.integer(
          'copyProgressMinBytes',
          defaultValue: LocalFsSettings.defaultCopyProgressMinBytes,
          title: 'Show progress inside a file from',
          unit: 'bytes',
          description: 'Below this size a copy is counted whole: the progress costs more than the copy',
          min: 0,
          max: 1024 * 1024 * 1024,
          read: () => settings.section(LocalFsSettings.new).copyProgressMinBytes,
          write: (value) => settings.section(LocalFsSettings.new).copyProgressMinBytes = value,
        ),
      ], save: settings.save),
    );

    // Буфер обмена: им пользуется просмотрщик, а дальше — команды «скопировать
    // путь» и «скопировать список имён».
    registry.service<ClipboardService>((services) => const SystemClipboard());

    // Отдать файл системной программе — действие экранное: за ним человек
    // уходит из приложения. Дереву оно ни к чему, а путь ему приносят готовым.
    registry.service<SystemOpener>((services) => openWithSystem);
    registry.service<WindowService>((services) => PluginWindowService());
  }
}
