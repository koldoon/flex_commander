import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'create_archive_command.dart';

/// Zip-архив как дерево — экранная половина: упаковка на `Shift-F5`.
///
/// Упаковка — такое же действие, как копирование, и живёт там же, где формат:
/// про zip знает только этот модуль.
class ZipArchiverFrontend implements FcFrontendModule {
  const ZipArchiverFrontend();

  @override
  String get id => 'fc.zip_archiver';

  @override
  String get title => 'Zip archives';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.command((context) => CreateZipArchiveCommand(staging: context.resolve<StagingArea>()));
    registry.binding(KeyBinding('Shift-F5', CreateZipArchiveCommand.commandId));
  }
}
