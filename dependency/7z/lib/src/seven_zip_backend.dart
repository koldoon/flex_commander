import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'seven_zip_cli.dart';
import 'seven_zip_settings.dart';
import 'seven_zip_pack.dart';
import 'seven_zip_tree_provider.dart';

/// Архив 7z как дерево — ядровая половина.
///
/// Ядру про архивы знать нечего: модуль объявляет схему пути и расширения, по
/// которым файл открывается как каталог.
///
/// Модуль ставится и там, где программы 7-Zip нет: схема остаётся, а обращение
/// к архиву кончается внятной ошибкой. Молчаливое «ничего не происходит» было
/// бы хуже — пользователю неоткуда узнать, чего не хватает.
class SevenZipArchiverBackend implements FcBackendModule {
  const SevenZipArchiverBackend();

  @override
  String get id => 'fc.7z_archiver';

  @override
  String get title => '7z archives';

  @override
  void installBackend(BackendRegistry registry) {
    // Раздел настроек берётся здесь, а не в фабрике: реестр отдаёт раздел
    // тому, кто устанавливается сейчас, и спрошенный позже он оказался бы
    // чужим. Содержимое раздела к моменту вызова фабрики уже прочитано.
    final settings = registry.settings;

    // Программа одна на приложение: она запоминает, где лежит и какие ключи
    // понимает, и выяснять это заново на каждом архиве незачем.
    registry.service<SevenZipCli>(
      (services) => SevenZipCli(
        processes: services.resolve<ProcessRunner>(),
        executable: settings.section(SevenZipSettings.new).binary,
      ),
    );

    // Упаковка — работа ядра: обход дерева и запуск программы по эту сторону
    // границы.
    registry.operation(
      SevenZipPacking.kind,
      (services) =>
          SevenZipPacking(staging: services.resolve<StagingArea>(), cli: services.resolve<SevenZipCli>()).operation(),
    );

    registry.provider(
      SevenZipTreeProvider.schemeName,
      // Архив внутри архива сперва оказывается на диске, но где именно —
      // знает не архиватор: место под временные файлы даёт приложение.
      () => TaskOperation<FsNode, TreeProvider>((op, host) {
        op.message('Reading ${host.name}…');
        return ProviderRegistry.keepUnlessCanceled(
          op,
          SevenZipTreeProvider.open(
            host,
            staging: registry.services.resolve<StagingArea>(),
            cli: registry.services.resolve<SevenZipCli>(),
            // Архив под паролем спросит его сам — тем же способом, каким это
            // делает подключение к серверу.
            credentials: registry.services.resolve<Credentials>(),
            // Копирование архива во временный файл — самая долгая часть
            // открытия, и о ней стоит рассказывать.
            onBytes: (bytes) => op.report(message: 'Reading ${host.name}…', bytesTransferred: bytes),
          ),
        );
      }),
      extensions: SevenZipTreeProvider.extensions,
    );
  }
}
