import 'package:fc_api/fc_api.dart';

import 'local_fs_settings.dart';
import 'local_process_runner.dart';
import 'local_staging_area.dart';
import 'local_tree_provider.dart';
import 'plugin_window_service.dart';
import 'system_clipboard.dart';
import 'system_open.dart';

/// Локальная файловая система: корневой источник, окно и всё платформенное.
///
/// Оформлен модулем, как и остальное, но живёт в ядре: без локальной ФС нельзя
/// прочитать даже собственные настройки приложения. Раскладка каталога такая,
/// чтобы вынос в отдельный пакет свёлся к переносу файлов.
class LocalFileSystem implements FcModule {
  const LocalFileSystem();

  @override
  String get id => 'fc.local_fs';

  @override
  String get title => 'Local file system';

  @override
  void install(FcRegistry registry) {
    // Раздел настроек берётся не сейчас, а по надобности: сам файл настроек
    // лежит в домашнем каталоге, а где он — знает провайдер, который здесь
    // только создаётся.
    final settings = registry.settings;

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.integer(
          'copyProgressMinBytes',
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
    registry.rootProvider(
      (services) => LocalTreeProvider(
        settings: () => settings.section(LocalFsSettings.new),
        // Чем запускать оболочку — вещь пользовательская, и живёт она в
        // настройках терминала. Спрашивается необязательно и лениво: без
        // модуля терминала объявить её некому, и тогда берётся `$SHELL`.
        shellName: () => services.resolveAll<ShellPreference>().firstOrNull?.shell ?? '',
        // Повышение прав — тоже необязательно и тоже лениво: службу объявляет
        // ядро, а провайдер создаётся раньше него.
        elevation: () => services.resolveAll<Elevation>().firstOrNull,
      ),
    );

    // Место для временных файлов: им пользуются те, кому нужен настоящий файл
    // на диске, — архиватор и будущие сетевые источники.
    registry.service<StagingArea>((services) => const LocalStagingArea());

    // Запуск программ: им пользуются модули, которые стоят над внешним
    // инструментом, — архиватор 7z и будущие сетевые источники.
    registry.service<ProcessRunner>((services) => const LocalProcessRunner());

    registry.service<SystemOpener>((services) => openWithSystem);

    // Буфер обмена: им пользуется просмотрщик, а дальше — команды «скопировать
    // путь» и «скопировать список имён».
    registry.service<ClipboardService>((services) => const SystemClipboard());
    registry.service<WindowService>((services) => PluginWindowService());
  }
}
