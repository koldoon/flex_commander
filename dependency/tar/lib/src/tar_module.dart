import 'package:fc_api/fc_api.dart';

import 'create_archive_command.dart';
import 'gzip_tree_provider.dart';
import 'tar_tree_provider.dart';

/// Архивы tar, gz и tar.gz.
///
/// Провайдера два, потому что форматы разные по сути: tar — контейнер без
/// сжатия, gz — сжатие одного потока. `.tar.gz` получается их цепочкой, и
/// особого случая для двойного расширения писать не приходится.
class TarArchiver implements FcModule {
  const TarArchiver();

  @override
  String get id => 'fc.tar_archiver';

  @override
  String get title => 'Tar archives';

  @override
  void install(FcRegistry registry) {
    registry.provider(
      TarTreeProvider.schemeName,
      () => TaskOperation<FsNode, TreeProvider>((op, host) {
        op.message('Reading ${host.name}…');
        return ProviderRegistry.keepUnlessCanceled(
          op,
          TarTreeProvider.open(
            host,
            // Архив внутри архива или на сервере сперва оказывается на диске,
            // но где именно — знает не архиватор: место даёт приложение.
            staging: registry.services.resolve<StagingArea>(),
            // Для `.tar.gz` это и есть распаковка: самая долгая часть
            // открытия, и молчать о ней нельзя.
            onBytes: (bytes) => op.report(message: 'Reading ${host.name}…', bytesTransferred: bytes),
            // Оглавления у формата нет, и открытие стоит прохода по всему
            // файлу: на большом архиве это единственное, что говорит о работе,
            // и единственное место, где слышно `Esc`.
            checkpoint: op.checkpoint,
            onEntries: (entries) => op.message('Reading ${host.name}… $entries entries'),
          ),
        );
      }),
      extensions: TarTreeProvider.extensions,
    );

    registry.provider(
      GzipTreeProvider.schemeName,
      // Тут работы нет вовсе: узнать имя и размер — это заголовок и хвост
      // файла. Разжимает содержимое тот, кому нужен настоящий файл.
      () => TaskOperation<FsNode, TreeProvider>((op, host) => GzipTreeProvider.open(host)),
      extensions: GzipTreeProvider.extensions,
    );

    // Упаковка — такое же действие, как копирование, и живёт там же, где
    // формат. Клавиши ей не досталось: `Shift-F5` у zip, `Shift-F7` у 7z, а
    // `Shift-F6` встал бы поперёк привычки — `F6` это перенос. Место команды
    // без клавиши — палитра.
    registry.command((context) => CreateTarArchiveCommand(staging: context.resolve<StagingArea>()));
  }
}
