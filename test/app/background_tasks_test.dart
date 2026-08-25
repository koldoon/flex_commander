import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Длительная работа, которой можно управлять из теста.
class _SlowCommand extends AsyncCommandBase {
  _SlowCommand(this.operation);

  final TaskOperation<void> operation;

  @override
  String get id => 'test.slow';

  @override
  String get label => 'Slow work';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() => runOperation(operation, message: 'Working…');
}

class _SlowModule implements FcModule {
  _SlowModule(this.operation);

  final TaskOperation<void> operation;

  @override
  String get id => 'test.slow';

  @override
  String get title => 'Slow work';

  @override
  void install(FcRegistry registry) => registry.command((context) => _SlowCommand(operation));
}

void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home')]);
  });

  /// Работа, которая идёт, пока её не отпустят.
  ({TaskOperation<void> operation, void Function() finish}) blockingOperation() {
    var done = false;
    final operation = TaskOperation<void>((op) async {
      while (!done) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await op.checkpoint();
      }
    });
    return (operation: operation, finish: () => done = true);
  }

  test('работа уходит в фон и остаётся в общем списке', () async {
    final work = blockingOperation();
    final runtime = await testApp(provider: provider, modules: [_SlowModule(work.operation)]);

    expect(runtime.commands.run('test.slow'), isTrue);
    final run = runtime.commands.openDialogs.single as AsyncCommandBase;
    unawaited(run.submit());
    await Future<void>.delayed(const Duration(milliseconds: 5));

    runtime.app.operations.sendToBackground(run.runId, owner: ViewportPosition.left);

    // Окна больше нет, а работа идёт — и видна там, где видны все такие.
    expect(runtime.commands.openDialogs, isEmpty);
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
    final runtime = await testApp(provider: provider, modules: [_SlowModule(work.operation)]);

    runtime.commands.run('test.slow');
    final run = runtime.commands.openDialogs.single as AsyncCommandBase;
    unawaited(run.submit());
    await Future<void>.delayed(const Duration(milliseconds: 5));

    runtime.app.operations.sendToBackground(run.runId, owner: ViewportPosition.left);
    runtime.app.operations.bringToFront(run.runId);

    expect(runtime.commands.openDialogs.single, same(run));
    expect([
      for (final run in runtime.app.operations.all)
        if (run.isInBackground) run,
    ], isEmpty);

    work.finish();
    await run.completion;
  });

  test('вопрос посреди фоновой работы окно не выдёргивает, а зажигает кнопку', () async {
    final work = blockingOperation();
    // Сообщение живёт дольше проверки: по умолчанию оно гаснет за пять
    // миллисекунд, а до заявки надо ещё дойти.
    final runtime = await testApp(
      provider: provider,
      modules: [_SlowModule(work.operation)],
      toastDuration: const Duration(seconds: 1),
    );

    runtime.commands.run('test.slow');
    final run = runtime.commands.openDialogs.single as AsyncCommandBase;
    unawaited(run.submit());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    runtime.app.operations.sendToBackground(run.runId, owner: ViewportPosition.left);

    // Прервать работу можно и из фона — но прерывание не молчаливое: операция
    // переспрашивает, и отвечать за пользователя ядро не вправе.
    final task = runtime.app.operations.at(ViewportPosition.left).single;
    expect(task.status.state.isFinished, isFalse);
    task.operation.requestCancel();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Окно само не выпрыгивает: вырывать человека из другого дела нельзя, а
    // вопрос никуда не денется — работа ждёт столько, сколько нужно.
    expect(runtime.app.operations.at(ViewportPosition.left), hasLength(1));
    expect(runtime.commands.openDialogs, isEmpty);
    expect(task.status.state, OperationState.userActionRequired, reason: 'у полоски загорается кнопка');
    // Но и молчать нельзя, иначе работа стоит, а человек этого не замечает.
    expect(runtime.app.toasts.current?.message, contains('waiting for an answer'));

    // Кнопка возвращает окно — и вопрос в нём.
    runtime.app.operations.bringToFront(task.runId);
    expect(runtime.commands.openDialogs.single, same(run));
    expect(run.question, isNotNull);

    // Enter отвечает вариантом по умолчанию — прервать.
    await run.submit();
    await run.completion;
    expect(run.isRunning, isFalse);
  });
}
