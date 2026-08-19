import 'package:fc_api/fc_api.dart';

import 'local_process_runner.dart';
import 'local_staging_area.dart';
import 'local_tree_provider.dart';
import 'plugin_window_service.dart';
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
    registry.rootProvider((services) => LocalTreeProvider());

    // Место для временных файлов: им пользуются те, кому нужен настоящий файл
    // на диске, — архиватор и будущие сетевые источники.
    registry.service<StagingArea>((services) => const LocalStagingArea());

    // Запуск программ: им пользуются модули, которые стоят над внешним
    // инструментом, — архиватор 7z и будущие сетевые источники.
    registry.service<ProcessRunner>((services) => const LocalProcessRunner());

    registry.service<SystemOpener>((services) => openWithSystem);
    registry.service<WindowService>((services) => PluginWindowService());
  }
}
