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

    runtime.app.background.sendToBackground(run.runId);

    // Окна больше нет, а работа идёт — и видна там, где видны все такие.
    expect(runtime.commands.openDialogs, isEmpty);
    expect(runtime.app.background.tasks, hasLength(1));
    expect(runtime.app.background.tasks.single.isRunning, isTrue);
    expect(runtime.app.background.isInBackground(run.runId), isTrue);

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

    runtime.app.background.sendToBackground(run.runId);
    runtime.app.background.bringToFront(run.runId);

    expect(runtime.commands.openDialogs.single, same(run));
    expect(runtime.app.background.tasks, isEmpty);

    work.finish();
    await run.completion;
  });

  test('вопрос посреди фоновой работы возвращает окно', () async {
    final work = blockingOperation();
    final runtime = await testApp(provider: provider, modules: [_SlowModule(work.operation)]);

    runtime.commands.run('test.slow');
    final run = runtime.commands.openDialogs.single as AsyncCommandBase;
    unawaited(run.submit());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    runtime.app.background.sendToBackground(run.runId);

    // Прервать работу можно и из фона — но прерывание не молчаливое: операция
    // переспрашивает, и отвечать за пользователя ядро не вправе.
    final task = runtime.app.background.tasks.single;
    expect(task.canCancel, isTrue);
    task.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(runtime.app.background.tasks, isEmpty, reason: 'вопрос вернул окно из фона');
    expect(runtime.commands.openDialogs.single, same(run));
    expect(run.question, isNotNull);

    // Enter отвечает вариантом по умолчанию — прервать.
    await run.submit();
    await run.completion;
    expect(run.isRunning, isFalse);
  });

  test('законченная работа уходит из списка', () async {
    final work = blockingOperation();
    final runtime = await testApp(provider: provider, modules: [_SlowModule(work.operation)]);

    runtime.commands.run('test.slow');
    final run = runtime.commands.openDialogs.single as AsyncCommandBase;
    unawaited(run.submit());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    runtime.app.background.sendToBackground(run.runId);

    work.finish();
    await run.completion;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(runtime.app.background.tasks, isEmpty);
  });
}
