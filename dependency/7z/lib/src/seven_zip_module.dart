import 'package:fc_api/fc_api.dart';

import 'create_archive_command.dart';
import 'seven_zip_cli.dart';
import 'seven_zip_settings.dart';
import 'seven_zip_tree_provider.dart';

/// Архив 7z как дерево.
///
/// Ядру про архивы знать нечего: модуль объявляет схему пути и расширения, по
/// которым файл открывается как каталог, и команду упаковки на `Shift-F7`.
///
/// Модуль ставится и там, где программы 7-Zip нет: схема остаётся, а обращение
/// к архиву кончается внятной ошибкой. Молчаливое «ничего не происходит» было
/// бы хуже — пользователю неоткуда узнать, чего не хватает.
class SevenZipArchiver implements FcModule {
  const SevenZipArchiver();

  @override
  String get id => 'fc.7z_archiver';

  @override
  String get title => '7z archives';

  @override
  void install(FcRegistry registry) {
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

    // Упаковка — такое же действие, как копирование, и живёт там же, где
    // формат: про 7z знает только этот модуль.
    registry.command(
      (context) =>
          CreateSevenZipArchiveCommand(staging: context.resolve<StagingArea>(), cli: context.resolve<SevenZipCli>()),
    );
    registry.binding(KeyBinding('Shift-F7', CreateSevenZipArchiveCommand.commandId));
  }
}
