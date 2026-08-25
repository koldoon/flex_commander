import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Длительная работа, которой можно управлять из теста.
///
/// Устроена как настоящие: показывает окно и уходит. Прогон она держит только
/// ради теста — ему нужно за что-то ухватиться.
class _SlowCommand extends AppCommand {
  _SlowCommand(this.operation);

  final TaskOperation<void, void> operation;

  FcAsyncRun? lastRun;

  @override
  String get id => 'test.slow';

  @override
  String get label => 'Slow work';

  String get dialogTitle => 'Slow work';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    late final FcAsyncRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(title: dialogTitle, content: const SizedBox.shrink(), onSubmit: run.submit, onDismiss: run.dismiss),
      );
    }

    run = FcAsyncRun(
      app: context.app,
      commandId: id,
      title: dialogTitle,
      failureMessage: 'Slow work failed',
      show: present,
    );
    run.onStart = () => run.run(operation, null, message: 'Working…');
    lastRun = run;

    present();
  }
}

class _SlowModule implements FcModule {
  _SlowModule(this.command);

  final _SlowCommand command;

  @override
  String get id => 'test.slow';

  @override
  String get title => 'Slow work';

  @override
  void install(FcRegistry registry) => registry.command((context) => command);
}

void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home')]);
  });

  /// Работа, которая идёт, пока её не отпустят.
  ({TaskOperation<void, void> operation, void Function() finish}) blockingOperation() {
    var done = false;
    final operation = TaskOperation<void, void>((op, _) async {
      while (!done) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await op.checkpoint();
      }
    });
    return (operation: operation, finish: () => done = true);
  }

  test('работа уходит в фон и остаётся в общем списке', () async {
    final work = blockingOperation();
    final command = _SlowCommand(work.operation);
    final runtime = await testApp(provider: provider, modules: [_SlowModule(command)]);

    expect(runtime.commands.run('test.slow'), isTrue);
    final run = command.lastRun!;
    unawaited(run.submit());
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // Убирает окно и оставляет работу идти — то же, что делает кнопка «в фон».
    run.sendToBackground();

    // Окна больше нет, а работа идёт — и видна там, где видны все такие.
    expect(runtime.app.view.dialogs, isEmpty);
    expect([
      for (final run in runtime.app.operations.all)
        if (run.isInBackground) run,
    ], hasLength(1));
    expect(
      [
        for (final run in runtime.app.operations.all)
          if (run.isInBackground) run,
      ].single.status.state,
      OperationState.processing,
    );
    expect(runtime.app.operations.byId(run.runId)?.isInBackground ?? false, isTrue);

    work.finish();
    await run.completion;
  });

  test('работу из фона можно вернуть на вид', () async {
    final work = blockingOperation();
    final command = _SlowCommand(work.operation);
    final runtime = await testApp(provider: provider, modules: [_SlowModule(command)]);

    runtime.commands.run('test.slow');
    final run = command.lastRun!;
    unawaited(run.submit());
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // Убирает окно и оставляет работу идти — то же, что делает кнопка «в фон».
    run.sendToBackground();
    runtime.app.operations.bringToFront(run.runId);

    expect(runtime.app.view.dialogs, hasLength(1));
    expect([
      for (final run in runtime.app.operations.all)
        if (run.isInBackground) run,
    ], isEmpty);

    work.finish();
    await run.completion;
  });

  test('вопрос посреди фоновой работы окно не выдёргивает, а зажигает кнопку', () async {
    final work = blockingOperation();
    final command = _SlowCommand(work.operation);
    // Сообщение живёт дольше проверки: по умолчанию оно гаснет за пять
    // миллисекунд, а до заявки надо ещё дойти.
    final runtime = await testApp(
      provider: provider,
      modules: [_SlowModule(command)],
      toastDuration: const Duration(seconds: 1),
    );

    runtime.commands.run('test.slow');
    final run = command.lastRun!;
    unawaited(run.submit());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    // Убирает окно и оставляет работу идти — то же, что делает кнопка «в фон».
    run.sendToBackground();

    // Прервать работу можно и из фона — но прерывание не молчаливое: операция
    // переспрашивает, и отвечать за пользователя ядро не вправе.
    final task = runtime.app.operations.at(ViewportPosition.left).single;
    expect(task.status.state.isFinished, isFalse);
    task.operation.requestCancel();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Окно само не выпрыгивает: вырывать человека из другого дела нельзя, а
    // вопрос никуда не денется — работа ждёт столько, сколько нужно.
    expect(runtime.app.operations.at(ViewportPosition.left), hasLength(1));
    expect(runtime.app.view.dialogs, isEmpty);
    expect(task.status.state, OperationState.userActionRequired, reason: 'у полоски загорается кнопка');
    // Но и молчать нельзя, иначе работа стоит, а человек этого не замечает.
    expect(runtime.app.toasts.current?.message, contains('waiting for an answer'));

    // Кнопка возвращает окно — и вопрос в нём.
    runtime.app.operations.bringToFront(task.runId);
    expect(runtime.app.view.dialogs, hasLength(1));
    expect(run.question, isNotNull);

    // Enter отвечает вариантом по умолчанию — прервать.
    await run.submit();
    await run.completion;
    expect(run.isRunning, isFalse);
  });
}
