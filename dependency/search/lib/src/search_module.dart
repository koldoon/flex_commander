import 'package:fc_api/fc_api.dart';

import 'find_files_command.dart';

/// Поиск по дереву и работа с найденным.
///
/// Быстрый поиск в панели живёт не здесь, а в навигации: он водит курсор по
/// списку, который и так на экране, и общего с обходом дерева у него нет
/// ничего (`spec/file-search.md`, §8).
class FileSearch implements FcModule {
  const FileSearch();

  static const String moduleId = 'fc.search';

  @override
  String get id => moduleId;

  @override
  String get title => 'File search';

  @override
  void install(FcRegistry registry) {
    registry.command((context) => FindFilesCommand());
    // Привычка Total Commander.
    registry.binding(KeyBinding('Alt-F7', FindFilesCommand.commandId));
  }
}
