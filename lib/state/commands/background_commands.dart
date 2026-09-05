/// Команды списка фоновых работ.
///
/// Спецификация — `docs/spec/background-operations.md`, §6.
library;

import 'package:fc_ui_api/fc_ui_api.dart';

import '../../view/background_tasks_view.dart';
import '../background_tasks_state.dart';

/// Список под названной панелью; null — там его нет.
BackgroundTasksState? _listAt(Application app, ViewportPosition panel) {
  final position = panel.status;
  if (position == null) {
    return null;
  }
  for (final state in app.view.stackAt(position)) {
    if (state is BackgroundTasksState) {
      return state;
    }
  }
  return null;
}

/// Список, в который ведёт `Cmd-B`: под активной панелью, а если там пусто —
/// под соседней.
///
/// Соседняя не прихоть: работу отправляют в фон с той стороны, где её завели, и
/// человек, глядящий на единственный список в окне, вправе попасть в него, не
/// переходя панелью.
BackgroundTasksState? _listToFocus(Application app) {
  final source = app.view.sourceArea;
  final other = source == ViewportPosition.left ? ViewportPosition.right : ViewportPosition.left;
  return _listAt(app, source) ?? _listAt(app, other);
}

/// Список, которому сейчас достаются клавиши.
BackgroundTasksState? _focusedList(Application app) {
  final content = app.view.contentAt(app.view.activeArea);
  return content is BackgroundTasksState ? content : null;
}

/// Отдать ввод списку фоновых работ.
class FocusBackgroundCommand extends AppCommand {
  static const String commandId = 'app.background';

  @override
  String get id => commandId;

  @override
  String get label => 'Background tasks';

  @override
  String get description => 'Move the input to the list of tasks running in background';

  @override
  Set<String> get keywords => const {'jobs', 'progress', 'cancel'};

  /// Работ нет — вести ввод некуда, и команда об этом говорит приглушённой
  /// кнопкой, а не молчаливым ничем.
  @override
  bool isExecutable(CommandContext context) => _listToFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final list = _listToFocus(context.app);
    if (list == null) {
      return;
    }
    context.app.view.setFocus(list.owner.status!);
  }
}

/// Вернуть ввод панели.
class LeaveBackgroundCommand extends AppCommand {
  static const String commandId = 'background.leave';

  @override
  String get id => commandId;

  @override
  String get label => 'Back to panel';

  @override
  bool isExecutable(CommandContext context) => _focusedList(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    // Ввод возвращается той панели, откуда пришли: у панельной области свой
    // признак активности, и отпускает ввод её `activate` — тот же путь, каким
    // из списка выходят мышью.
    context.app.view.setFocus(context.app.view.sourceArea);
  }
}

/// Курсор по списку.
class MoveBackgroundCursorCommand extends AppCommand {
  MoveBackgroundCursorCommand({required this.down});

  static const String upId = 'background.cursorUp';
  static const String downId = 'background.cursorDown';

  final bool down;

  @override
  String get id => down ? downId : upId;

  @override
  String get label => down ? 'Next task' : 'Previous task';

  @override
  bool isExecutable(CommandContext context) => (_focusedList(context.app)?.runs.length ?? 0) > 1;

  @override
  Future<void> execute(CommandContext context) async {
    final list = _focusedList(context.app);
    if (list == null) {
      return;
    }
    // Ход по списку — тот же, что у списков выбора: заворот кольцом и правило
    // края написаны там один раз.
    list.cursor = (list.cursor + (down ? 1 : -1)) % list.runs.length;
  }
}

/// Вернуть окно выбранной работы — то же, что щелчок по строке.
class ShowBackgroundTaskCommand extends AppCommand {
  static const String commandId = 'background.toFront';

  @override
  String get id => commandId;

  @override
  String get label => 'Show task';

  @override
  bool isExecutable(CommandContext context) => _focusedList(context.app)?.current != null;

  @override
  Future<void> execute(CommandContext context) async {
    final list = _focusedList(context.app);
    final task = list?.current;
    if (list == null || task == null) {
      return;
    }
    list.operations.bringToFront(task.runId);
  }
}

/// Отменить выбранную работу; законченную — забыть. То же, что крестик.
class CancelBackgroundTaskCommand extends AppCommand {
  static const String commandId = 'background.cancel';

  @override
  String get id => commandId;

  @override
  String get label => 'Cancel task';

  @override
  String get description => 'Stop the selected background task; a finished one is dismissed';

  @override
  bool isExecutable(CommandContext context) => _focusedList(context.app)?.current != null;

  @override
  Future<void> execute(CommandContext context) async {
    final list = _focusedList(context.app);
    final task = list?.current;
    if (list == null || task == null) {
      return;
    }
    cancelOrForgetTask(list.operations, task);
  }
}
