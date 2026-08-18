import '../../model/tree/fs_node.dart';
import 'app_command.dart';

/// Инвертировать пометку объекта под курсором и сдвинуть курсор вниз — так
/// несколько файлов подряд помечаются одной клавишей.
class ToggleMarkCommand extends AppCommand {
  @override
  String get id => 'panel.selection.toggle';

  @override
  String get label => 'Mark';

  @override
  String get description => 'Mark or unmark the item under the cursor and step down';

  @override
  bool isExecutable(CommandContext context) {
    final node = context.node;
    return node != null && node is! ParentDirNode;
  }

  @override
  Future<void> execute() async => context.panel.toggleCurrentMark();
}

/// Снять всю пометку.
class ClearSelectionCommand extends AppCommand {
  @override
  String get id => 'panel.selection.clear';

  @override
  String get label => 'Unmark all';

  @override
  String get description => 'Drop the marks, leaving the cursor where it is';

  @override
  bool isExecutable(CommandContext context) => context.panel.selection.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.selection.clear();
}

/// Пометить всё, кроме «..».
class SelectAllCommand extends AppCommand {
  @override
  String get id => 'panel.selection.all';

  @override
  String get label => 'Mark all';

  @override
  String get description => 'Mark everything in the current directory';

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute() async => context.panel.markAll();
}
