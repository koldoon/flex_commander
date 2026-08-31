/// Локальная файловая система и всё платформенное, что растёт из неё.
///
/// Модуль, как и остальные, но особого положения: без локальной ФС нельзя
/// прочитать даже собственные настройки приложения. Здесь же живёт всё, что
/// умеет только настоящая машина, — буфер обмена, запуск программ, открытие
/// файла системой, окно приложения.
library;

export 'src/local_file_system.dart';
export 'src/local_fs_settings.dart';
export 'src/local_listing.dart';
export 'src/local_mapping.dart';
export 'src/local_tree_provider.dart';
