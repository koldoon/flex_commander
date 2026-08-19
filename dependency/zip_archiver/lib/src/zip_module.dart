import 'package:fc_api/fc_api.dart';

import 'zip_tree_provider.dart';

/// Zip-архив как дерево.
///
/// Всё, что нужно ядру знать об архивах, — это одна регистрация: схема пути и
/// расширения, по которым файл открывается как каталог. Раньше эта строка
/// стояла в контейнере приложения.
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
      (host) => ZipTreeProvider.open(host, staging: registry.services.resolve<StagingArea>()),
      extensions: ZipTreeProvider.extensions,
    );
  }
}
