import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';
import 'app_scope.dart';

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
///
/// **Вопрос и ошибка — дочерними окнами, поверх, а не вместо.** Раньше они
/// подменяли ход работы, и человек отвечал, не видя, о чём речь. Теперь окно
/// работы остаётся с ходом дела на месте, а над ним, по его центру, встаёт
/// вопрос или разбор ошибки (`docs/spec/child-dialogs.md`, §4.2–4.3). Поднимает
/// их само окно: оно знает, кто его родитель, — себя.
class FcAsyncRunDialog extends StatefulWidget {
  const FcAsyncRunDialog({super.key, required this.run, required this.form});

  final FcAsyncRun run;

  /// Содержимое окна до начала работы: поля, подтверждение — что команде нужно.
  final WidgetBuilder form;

  @override
  State<FcAsyncRunDialog> createState() => _FcAsyncRunDialogState();
}

class _FcAsyncRunDialogState extends State<FcAsyncRunDialog> {
  FcAsyncRun get run => widget.run;

  /// Поднятое дочернее окно и то, ради чего оно поднято: вопрос или текст
  /// ошибки.
  String? _childId;
  Object? _childFor;

  @override
  void initState() {
    super.initState();
    run.addListener(_schedule);
    // Окно вернули из фона, а вопрос уже ждёт: поднять его сразу.
    _schedule();
  }

  @override
  void didUpdateWidget(FcAsyncRunDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.run, run)) {
      oldWidget.run.removeListener(_schedule);
      run.addListener(_schedule);
      _schedule();
    }
  }

  @override
  void dispose() {
    run.removeListener(_schedule);
    super.dispose();
  }

  /// Дочернее поднимается **после** кадра: окно нельзя показывать посреди
  /// уведомления или сборки.
  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    // Кадр — явно: отложенному подъёму нельзя зависеть от того, попросил ли
    // кадр кто-то ещё.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sync() {
    if (!mounted) {
      return;
    }
    final question = run.question;
    final failure = question == null && run.isBusy ? run.error : null;
    final wanted = question ?? failure;
    if (wanted == _childFor) {
      return;
    }
    // Стопка — у приложения прогона: окно работы и есть его окно.
    final view = run.app.view;
    if (_childId case final open?) {
      _childId = null;
      view.closeDialog(open);
    }
    _childFor = wanted;
    if (question != null) {
      _childId = view.showDialog(_questionSpec(question));
    } else if (failure != null) {
      _childId = view.showDialog(_failureSpec(failure));
    }
  }

  DialogSpec _questionSpec(OperationRequest question) => DialogSpec(
    parent: DialogScope.maybeOf(context),
    title: run.title,
    // Поле у вопроса есть, когда спрашивают имя: фокус ставит оно само.
    takesFocus: question.inputLabel != null,
    content: CommandDialogQuestion(request: question, onAnswer: run.answer, onTextChanged: run.setAnswerText),
    onSubmit: run.submit,
    // Вопрос без варианта для `Esc` закрыть нечем: на него надо ответить.
    onDismiss: question.escapeOption == null ? null : run.dismiss,
  );

  /// Разбор ошибки: кнопка закрывает **оба** окна — работа кончена, смотреть
  /// больше не на что (`docs/spec/child-dialogs.md`, §4.3).
  DialogSpec _failureSpec(String message) => DialogSpec(
    parent: DialogScope.maybeOf(context),
    title: run.title,
    content: CommandDialogConfirm(
      message: run.failureMessage,
      error: message,
      confirmLabel: context.strings.tr('Close'),
      onCancel: run.dismiss,
      onConfirm: run.dismiss,
    ),
    onSubmit: run.dismiss,
    onDismiss: run.dismiss,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        // Ход дела — только когда его есть что показывать
        // ([FcAsyncRun.showsProgress]). Работа, отказавшаяся мгновенно, не
        // должна мигнуть полосой на пути от формы обратно к форме. Вопрос и
        // ошибка его не прячут: они встают поверх.
        if (run.showsProgress) {
          return _progress();
        }

        return widget.form(context);
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
}
