import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

import 'command_dialog.dart';

/// Окно длительной работы.
///
/// Вопрос по ходу дела, ход дела и разбор ошибки одинаковы у всех таких окон и
/// потому собраны здесь. Снаружи приходит только то, с чего всё начинается, —
/// форма:
///
/// ```dart
/// FcAsyncRunDialog(run: run, form: _form)
/// ```
///
/// **Форма — не ветка «иначе», а состояние.** Она показывается ровно до тех
/// пор, пока прогон не начался. Как только работа пошла, окно к ней не
/// возвращается: в хвосте работы — отпустить аренду, перечитать панели —
/// операции уже нет, а окно ещё открыто, и раньше в этот промежуток на экран
/// выскакивала форма с параметрами.
class FcAsyncRunDialog extends StatelessWidget {
  const FcAsyncRunDialog({super.key, required this.run, required this.form});

  final FcAsyncRun run;

  /// Содержимое окна до начала работы: поля, подтверждение — что команде нужно.
  final WidgetBuilder form;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        final question = run.question;
        if (question != null) {
          return CommandDialogQuestion(request: question, onAnswer: run.answer, onTextChanged: run.setAnswerText);
        }

        if (run.isBusy) {
          final failure = run.error;
          // Ошибка после начала работы форму не воскрешает: править ввод уже
          // поздно, работа была начата. Остаётся сказать, что не вышло.
          return failure != null ? _failure(failure) : _progress();
        }

        return form(context);
      },
    );
  }

  Widget _progress() {
    // Кнопки живы, пока живо то, на что они действуют: у законченной работы
    // прерывать нечего и прятать нечего.
    final running = run.isRunning;

    return CommandDialogProgress(
      progress: run.progress,
      message: run.progressMessage,
      stageLabel: run.stageLabel,
      processed: run.processed,
      total: run.total,
      totalIsFinal: run.totalIsFinal,
      bytes: run.bytes,
      totalBytes: run.totalBytes,
      bytesPerSecond: run.bytesPerSecond,
      remaining: run.remaining,
      itemName: run.itemName,
      itemProgress: run.itemProgress,
      itemBytes: run.itemBytes,
      itemTotalBytes: run.itemTotalBytes,
      onCancel: running ? run.cancel : null,
      canBackground: run.canBackground,
      onBackground: running && run.canBackground ? run.sendToBackground : null,
    );
  }

  Widget _failure(String message) => CommandDialogConfirm(
    message: run.failureMessage,
    error: message,
    confirmLabel: 'Close',
    onCancel: run.dismiss,
    onConfirm: run.dismiss,
  );
}
