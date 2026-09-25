import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'undo_plan.dart';
import 'undo_work.dart';

/// Отменить последнюю файловую работу (`docs/spec/operation-history.md`).
///
/// Перед откатом — окно с перечнем: не «уверены?», а что именно произойдёт.
/// Ошибиться `Cmd-Z` слишком легко, а удаление созданного — настоящее
/// удаление (§10).
class UndoCommand extends AppCommand {
  UndoCommand(this.history);

  static const String commandId = 'history.undo';

  final OperationHistory history;

  @override
  String get id => commandId;

  @override
  String get label => tr('Undo');

  @override
  String get description => tr('Undo the last file operation, if it can be undone');

  @override
  Set<String> get keywords => const {'revert', 'back'};

  /// Ничего не делали — и отменять нечего: молчание здесь честно.
  ///
  /// А вот работа, которую отменить **нельзя**, команду не гасит: `Cmd-Z`
  /// обязан сказать почему, а не промолчать.
  @override
  bool isExecutable(CommandContext context) => history.last != null;

  /// Что именно отменяем; null — нечего.
  HistoryRecord? get _target => history.undoTarget;

  @override
  Future<void> execute(CommandContext context) async {
    final record = _target;
    if (record == null && history.undoObstacle == null) {
      return;
    }

    final obstacle = history.undoObstacle;
    if (obstacle != null) {
      await askConfirm(
        context.app,
        title: tr('Undo'),
        message: '${tr('This work cannot be undone')}: ${tr(obstacle)}',
        confirmLabel: tr('Close'),
        onConfirm: () {},
      );
      return;
    }

    final plan = UndoPlan.of(record!.journal);
    var agreed = false;
    await askConfirm(
      context.app,
      title: tr('Undo'),
      message: plan.describe(context.app.strings),
      confirmLabel: tr('Undo'),
      onConfirm: () => agreed = true,
    );
    if (!agreed) {
      return;
    }

    // Каталоги, которых коснётся откат, — до работы: после неё этих объектов
    // уже нет.
    final places = plan.places;

    final view = context.app.view;
    late final FcAsyncRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: tr('Undo'),
          takesFocus: true,
          // Своего у окна ничего нет: спрашивать нечего, всё уже спрошено.
          content: FcAsyncRunDialog(run: run, form: (_) => const SizedBox.shrink()),
          onDismiss: run.dismiss,
        ),
      );
    }

    run = FcAsyncRun(
      app: context.app,
      commandId: id,
      title: tr('Undo'),
      failureMessage: tr('Undo failed'),
      show: present,
    );

    present();
    try {
      await run.run(
        context.app.runOperation(),
        OperationSpec(
          kind: HistoryOperations.undo,
          // Целей нет: каждый путь работа разбирает сама (§9).
          options: {
            HistoryOperations.journal: [for (final entry in record.journal) entry.toMap()],
          },
        ),
        message: tr('Undoing…'),
      );
      // Работа отменена — второй раз её не отменяют: сделанного ею на диске
      // больше нет, а следующий `Cmd-Z` должен взяться за предыдущую
      // (`docs/spec/operation-history.md`, §9).
      history.markUndone(record.runId);
    } finally {
      await reloadPanelsAt(context.app, places);
    }
  }
}
