/// То, что умеет только настоящая машина.
///
/// Здесь живут реализации служб, объявленных в `fc_api`: окно, буфер обмена,
/// запуск программ, псевдотерминал, открытие файла системой, временные
/// каталоги. Плюс примитивы, которых нет в `dart:io`, — `copyfile(3)` и
/// `chmod(2)` через FFI.
///
/// **Не модуль.** Регистрировать здесь нечего: пакет отдаёт реализации, а кто
/// и под какими контрактами их объявит, решает тот, кто собирает приложение.
/// Поэтому ядру знать о нём можно — как о `fc_api` и `fc_ui_kit`.
///
/// Отделено от локальной файловой системы нарочно: провайдер дерева — это одно
/// умение, а «машина, на которой всё запущено» — другое. Когда дойдут руки до
/// второй операционной системы, менять придётся ровно этот пакет.
library;

export 'src/local_file_copy.dart';
export 'src/local_mode.dart';
export 'src/local_process_runner.dart';
export 'src/local_shell.dart';
export 'src/local_staging_area.dart';
export 'src/plugin_window_service.dart';
export 'src/posix_pty.dart';
export 'src/system_clipboard.dart';
export 'src/system_errors.dart';
export 'src/system_open.dart';
export 'src/system_pty.dart';
