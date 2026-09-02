import 'package:fc_ui_api/fc_ui_api.dart';

import 'create_archive_command.dart';
import 'seven_zip_settings.dart';

/// Архив 7z как дерево — экранная половина: упаковка на `Shift-F7` и раздел
/// настроек с путём к программе.
class SevenZipArchiverFrontend implements FcFrontendModule {
  const SevenZipArchiverFrontend();

  @override
  String get id => 'fc.7z_archiver';

  @override
  String get title => '7z archives';

  @override
  void installFrontend(FrontendRegistry registry) {
    // Раздел тот же, что у ядровой половины: имя одно на модуль, а файл
    // настроек принадлежит ядру.
    final settings = registry.settings;

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.text(
          'binary',
          title: '7z program',
          hint: 'found on PATH',
          description: 'Full path — for when it is installed somewhere unusual',
          note: 'Applies to the next archive opened',
          read: () => settings.section(SevenZipSettings.new).binary,
          write: (value) => settings.section(SevenZipSettings.new).binary = value,
        ),
      ], save: settings.save),
    );

    // Упаковка — такое же действие, как копирование, и живёт там же, где
    // формат: про 7z знает только этот модуль.
    registry.command((context) => CreateSevenZipArchiveCommand());
    registry.binding(KeyBinding('Shift-F7', CreateSevenZipArchiveCommand.commandId));
  }
}
