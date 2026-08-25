import 'package:fc_api/fc_api.dart';

import 'create_archive_command.dart';
import 'zip_tree_provider.dart';

/// Zip-архив как дерево.
///
/// Ядру про архивы знать нечего: модуль объявляет схему пути и расширения, по
/// которым файл открывается как каталог, и команду упаковки на `Shift-F5`.
class ZipArchiver implements FcModule {
  const ZipArchiver();

  @override
  String get id => 'fc.zip_archiver';

  @override
  String get title => 'Zip archives';

  @override
  void install(FcRegistry registry) {
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
            onBytes: (bytes) => op.report(OperationProgress(message: 'Reading ${host.name}…', bytes: bytes)),
          ),
        );
      }),
      extensions: ZipTreeProvider.extensions,
    );

    // Упаковка — такое же действие, как копирование, и живёт там же, где
    // формат: про zip знает только этот модуль.
    registry.command((context) => CreateZipArchiveCommand(staging: context.resolve<StagingArea>()));
    registry.binding(KeyBinding('Shift-F5', CreateZipArchiveCommand.commandId));
  }
}
