import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'create_archive_command.dart';
import 'zip_pack.dart';
import 'zip_tree_provider.dart';

/// Zip-архив как дерево — и то, чем его упаковывают.
///
/// Один класс на обе стороны: половины у модуля разные, а модуль один — тот же
/// идентификатор, тот же раздел настроек, та же строка в справке. Что куда
/// объявляется, решает не класс, а реестр: окно из [installBackend] объявить
/// нечем, источник из [installFrontend] — тоже (`docs/modules.md`).
class ZipArchiver implements FcBackendModule, FcFrontendModule {
  const ZipArchiver();

  @override
  String get id => 'fc.zip_archiver';

  @override
  String get title => 'Zip archives';

  /// Ядру про архивы знать нечего: модуль объявляет схему пути и расширения, по
  /// которым файл открывается как каталог.
  @override
  void installBackend(BackendRegistry registry) {
    // Упаковка — такое же дело, как копирование, и живёт там же, где формат.
    // Работой, а не командой: обход дерева и байты — по эту сторону границы.
    registry.operation(ZipPacking.kind, (services) => ZipPacking(staging: services.resolve<StagingArea>()).operation());

    registry.provider(
      ZipTreeProvider.schemeName,
      // Архив внутри архива сперва оказывается на диске, но где именно —
      // знает не архиватор: место под временные файлы даёт приложение.
      () => TaskOperation<FsNode, TreeProvider>((op, host) {
        op.message('Reading ${host.name}…');
        return ProviderRegistry.keepUnlessCanceled(
          op,
          ZipTreeProvider.open(
            host,
            staging: registry.services.resolve<StagingArea>(),
            // Зашифрованная запись спросит пароль сама — тем же способом, каким
            // это делает 7z и делает подключение к серверу.
            credentials: registry.services.resolve<Credentials>(),
            // Архив с сервера сперва копируется целиком, и это самая долгая
            // часть открытия: молчать о ней нельзя.
            onBytes: (bytes) => op.report(message: 'Reading ${host.name}…', bytesTransferred: bytes),
          ),
        );
      }),
      extensions: ZipTreeProvider.extensions,
    );
  }

  /// Упаковка — такое же действие, как копирование, и живёт там же, где формат:
  /// про zip знает только этот модуль.
  @override
  void installFrontend(FrontendRegistry registry) {
    registry.command((context) => CreateZipArchiveCommand());
    registry.binding(KeyBinding('Shift-F5', CreateZipArchiveCommand.commandId));
  }
}
