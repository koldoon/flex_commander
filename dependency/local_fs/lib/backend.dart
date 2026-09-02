/// Локальная файловая система: то, что живёт в ядре.
///
/// Корневой источник, оболочка этой машины, место под временные файлы, запуск
/// программ и открытие файла системой — всё то, что умеет только настоящая
/// машина и что нужно там, где живут источники.
library;

export 'src/local_fs_backend.dart';
export 'src/local_fs_settings.dart';
export 'src/local_listing.dart';
export 'src/local_mapping.dart';
export 'src/local_tree_provider.dart';
