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
  List<KeyBinding> get bindings => [KeyBinding('Space'), KeyBinding('Ins')];

  @override
  bool isExecutable(CommandContext context) {
    final node = context.node;
    return node != null && node is! ParentDirNode;
  }

  @override
  Future<void> execute(CommandContext context) async => context.panel.toggleCurrentMark();
}

/// Снять всю пометку.
class ClearSelectionCommand extends AppCommand {
  @override
  String get id => 'panel.selection.clear';

  @override
  String get label => 'Unmark all';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Esc')];

  @override
  bool isExecutable(CommandContext context) => context.panel.selection.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.selection.clear();
}

/// Пометить всё, кроме «..».
class SelectAllCommand extends AppCommand {
  @override
  String get id => 'panel.selection.all';

  @override
  String get label => 'Mark all';

  @override
  List<KeyBinding> get bindings => [KeyBinding('Cmd-A')];

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async => context.panel.markAll();
}
