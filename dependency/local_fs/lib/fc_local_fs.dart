/// Локальная файловая система и всё платформенное, что растёт из неё.
///
/// Модуль, как и остальные, но особого положения: без локальной ФС нельзя
/// прочитать даже собственные настройки приложения. Здесь же живёт всё, что
/// умеет только настоящая машина, — буфер обмена, запуск программ, открытие
/// файла системой, окно приложения.
library;

export 'src/local_file_copy.dart';
export 'src/local_file_system.dart';
export 'src/local_fs_settings.dart';
export 'src/local_listing.dart';
export 'src/local_mapping.dart';
export 'src/local_process_runner.dart';
export 'src/local_shell.dart';
export 'src/local_staging_area.dart';
export 'src/posix_pty.dart';
export 'src/local_tree_provider.dart';
export 'src/plugin_window_service.dart';
export 'src/system_clipboard.dart';
export 'src/system_pty.dart';
export 'src/system_open.dart';
