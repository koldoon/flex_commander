import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'gzip_tree_provider.dart';
import 'gzip_pack.dart';
import 'tar_pack.dart';
import 'tar_tree_provider.dart';

/// Архивы tar, gz и tar.gz — ядровая половина.
///
/// Провайдера два, потому что форматы разные по сути: tar — контейнер без
/// сжатия, gz — сжатие одного потока. `.tar.gz` получается их цепочкой, и
/// особого случая для двойного расширения писать не приходится.
class TarArchiverBackend implements FcBackendModule {
  const TarArchiverBackend();

  @override
  String get id => 'fc.tar_archiver';

  @override
  String get title => 'Tar archives';

  @override
  void installBackend(BackendRegistry registry) {
    // Упаковка — работа ядра: обход дерева и байты по эту сторону границы.
    registry.operation(
      GzipPacking.kind,
      (services) => GzipPacking(staging: services.resolve<StagingArea>()).operation(),
    );
    registry.operation(TarPacking.kind, (services) => TarPacking(staging: services.resolve<StagingArea>()).operation());

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
  }
}
