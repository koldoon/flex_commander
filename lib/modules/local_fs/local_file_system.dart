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
    registry.rootProvider((services) => LocalTreeProvider(settings: () => settings.section(LocalFsSettings.new)));

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
