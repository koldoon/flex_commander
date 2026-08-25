/// Подставные зависимости для тестов: дерево в памяти вместо файловой системы
/// и окно, которое ничего не открывает.
///
/// Живут отдельным пакетом, а не в `test/`: Dart не даёт импортировать каталог
/// тестов чужого пакета, а тесты модулей должны собирать приложение из тех же
/// подставок, что и тесты ядра.
library;

export 'src/command_run.dart';
export 'src/fake_clipboard.dart';
export 'src/fake_credentials.dart';
export 'src/fake_process_runner.dart';
export 'src/fake_window_service.dart';
export 'src/in_memory_settings_store.dart';
export 'src/in_memory_tree_provider.dart';
export 'src/test_app.dart';
export 'src/test_panel.dart';
export 'src/test_screen.dart';
