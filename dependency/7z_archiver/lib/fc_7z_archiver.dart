/// Архив 7z как дерево: панель входит в него, как в каталог.
///
/// Формат читается и пишется программой `7z`: своей реализации 7z в Dart нет,
/// и это не выбор, а положение дел — см. `docs/providers.md`.
library;

export 'src/seven_zip_cli.dart';
export 'src/seven_zip_listing.dart';
export 'src/seven_zip_module.dart';
export 'src/seven_zip_settings.dart';
export 'src/seven_zip_tree_provider.dart';
