import 'package:fc_ui_api/fc_ui_api.dart';

import 'create_archive_command.dart';
import 'create_gzip_command.dart';

/// Архивы tar, gz и tar.gz — экранная половина: две команды упаковки.
class TarArchiverFrontend implements FcFrontendModule {
  const TarArchiverFrontend();

  @override
  String get id => 'fc.tar_archiver';

  @override
  String get title => 'Tar archives';

  @override
  void installFrontend(FrontendRegistry registry) {
    // Упаковка — такое же действие, как копирование, и живёт там же, где
    // формат. Клавиши ей не досталось: `Shift-F5` у zip, `Shift-F7` у 7z, а
    // `Shift-F6` встал бы поперёк привычки — `F6` это перенос. Место команды
    // без клавиши — палитра.
    registry.command((context) => CreateTarArchiveCommand());

    // Сжатие одного файла — отдельная команда, а не пункт в окне упаковки:
    // gzip жмёт поток, а не набор файлов, и «сложить три файла в один .gz» —
    // просьба, которую формат не выполняет.
    registry.command((context) => CreateGzipCommand());
  }
}
