/// Архив 7z как дерево: то, что живёт в ядре.
///
/// Формат читается и пишется программой `7z`: своей реализации 7z в Dart нет,
/// и это не выбор, а положение дел — см. `docs/providers.md`.
library;

export 'src/seven_zip_backend.dart';
export 'src/seven_zip_cli.dart';
export 'src/seven_zip_listing.dart';
export 'src/seven_zip_settings.dart';
export 'src/seven_zip_tree_provider.dart';
