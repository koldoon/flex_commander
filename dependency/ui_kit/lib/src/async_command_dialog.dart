import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';

import 'command_dialog.dart';

/// Окно команды с длительной работой.
///
/// Вопрос по ходу дела, ход дела и разбор ошибки одинаковы у всех таких команд,
/// и потому собраны здесь. Команда даёт только то, с чего всё начинается, —
/// свою форму:
///
/// ```dart
/// @override
/// DialogSpec? dialogSpec(BuildContext context) =>
///     DialogSpec(title: dialogTitle, content: AsyncCommandDialog(command: this, form: _form));
/// ```
///
/// Подписку на команду ставит окно: состояние исполнения меняется её же
/// уведомлением.
///
/// **Форма — не ветка «иначе», а состояние.** Она показывается ровно до тех
/// пор, пока прогон не начался ([CommandRunPhase.idle]). Как только работа
/// пошла, окно к ней не возвращается: в хвосте работы — отпустить аренду,
/// перечитать панели — операции уже нет, а окно ещё открыто, и раньше в этот
/// промежуток на экран выскакивала форма с параметрами.
class AsyncCommandDialog extends StatelessWidget {
  const AsyncCommandDialog({super.key, required this.command, required this.form});

  final AsyncCommandBase command;

  /// Содержимое окна до начала работы: поля, подтверждение — что команде нужно.
  final WidgetBuilder form;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: command,
      builder: (context, _) {
        final question = command.question;
        if (question != null) {
          return CommandDialogQuestion(
            request: question,
            onAnswer: command.answer,
            onTextChanged: command.setAnswerText,
          );
        }

        if (command.isBusy) {
          final failure = command.error;
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
    final running = command.isRunning;

    return CommandDialogProgress(
      progress: command.progress,
      message: command.progressMessage,
      stageLabel: command.stageLabel,
      processed: command.processed,
      total: command.total,
      totalIsFinal: command.totalIsFinal,
      bytes: command.bytes,
      totalBytes: command.totalBytes,
      bytesPerSecond: command.bytesPerSecond,
      remaining: command.remaining,
      itemName: command.itemName,
      itemProgress: command.itemProgress,
      itemBytes: command.itemBytes,
      itemTotalBytes: command.itemTotalBytes,
      onCancel: running ? command.cancel : null,
      canBackground: command.canRunInBackground,
      onBackground: running && command.canRunInBackground ? command.sendToBackground : null,
    );
  }

  Widget _failure(String message) => CommandDialogConfirm(
    message: command.failureMessage,
    error: message,
    confirmLabel: 'Close',
    onCancel: command.dismiss,
    onConfirm: command.dismiss,
  );
}
