import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Инвертировать пометку объекта под курсором и сдвинуть курсор вниз — так
/// несколько файлов подряд помечаются одной клавишей.
class ToggleMarkCommand extends AppCommand {
  static const String commandId = 'panel.selection.toggle';

  @override
  String get id => commandId;

  @override
  String get label => 'Mark';

  @override
  String get description => 'Mark or unmark the item under the cursor and step down';

  @override
  Set<String> get keywords => const {'select', 'toggle selection'};

  @override
  bool isExecutable(CommandContext context) {
    final entry = context.entry;
    return entry != null && !entry.isParent;
  }

  @override
  Future<void> execute(CommandContext context) async => context.panel.toggleCurrentMark();
}

/// Снять всю пометку.
class ClearSelectionCommand extends AppCommand {
  static const String commandId = 'panel.selection.clear';

  @override
  String get id => commandId;

  @override
  String get label => 'Unmark all';

  @override
  String get description => 'Drop the marks, leaving the cursor where it is';

  @override
  Set<String> get keywords => const {'deselect', 'clear selection', 'none'};

  @override
  bool isExecutable(CommandContext context) => context.panel.marked.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.clearMarks();
}

/// Пометить файлы, не трогая каталоги.
///
/// Отдельная команда, а не оговорка у [SelectAllCommand]: «пометить всё» и
/// «пометить файлы» — разные намерения, и переключателем их не свести. Копируют
/// обычно всё, а вот `chmod +x`, упаковка и удаление по маске чаще касаются
/// именно файлов, и обходить каталоги руками в такой пометке — самое утомимое,
/// что есть.
///
/// Что считать файлом, решает она сама: каталог отсеивается **отдельной
/// проверкой**, и это не перестраховка — `DirectoryNode` наследник `FileNode`,
/// и проверка «это файл» молча пропустила бы каталоги.
class SelectFilesCommand extends AppCommand {
  static const String commandId = 'panel.selection.files';

  @override
  String get id => commandId;

  @override
  String get label => 'Mark files';

  @override
  String get description => 'Mark files in the current directory, leaving directories alone';

  @override
  Set<String> get keywords => const {'select files', 'only files'};

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.any(_isFile);

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    panel.setMarks({
      ...panel.marked,
      for (final entry in panel.entries)
        if (_isFile(entry)) entry.name,
    });
  }

  /// «..» отсеивать не нужно: его не берёт сама пометка.
  static bool _isFile(FileEntry entry) => !entry.isDirectory && !entry.isParent;
}

/// Пометить всё, кроме «..».
class SelectAllCommand extends AppCommand {
  static const String commandId = 'panel.selection.all';

  @override
  String get id => commandId;

  @override
  String get label => 'Mark all';

  @override
  String get description => 'Mark everything in the current directory';

  @override
  Set<String> get keywords => const {'select all', 'everything'};

  @override
  bool isExecutable(CommandContext context) => context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.markAll();
}
