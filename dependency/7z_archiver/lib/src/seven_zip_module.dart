import 'package:fc_api/fc_api.dart';

import 'seven_zip_cli.dart';
import 'seven_zip_settings.dart';
import 'seven_zip_tree_provider.dart';

/// Архив 7z как дерево.
///
/// Ядру про архивы знать нечего: модуль объявляет схему пути и расширения, по
/// которым файл открывается как каталог.
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
      (host) => SevenZipTreeProvider.open(
        host,
        staging: registry.services.resolve<StagingArea>(),
        cli: registry.services.resolve<SevenZipCli>(),
      ),
      extensions: SevenZipTreeProvider.extensions,
    );
  }
}
