import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Команда с длительной работой: что она делает с потоком сообщений о ходе дела.
class _ProbeCommand extends AsyncCommandBase {
  @override
  String get id => 'test.probe';

  @override
  String get label => 'Probe';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() async {}

  Future<void> run(AsyncOperation<void> operation) => runOperation(operation, message: 'Working…');
}

/// Команда, которая считает, сколько раз её попросили работать и сколько раз
/// работа действительно пошла.
class _CountingCommand extends AsyncCommandBase {
  int attempts = 0;
  int runs = 0;

  @override
  String get id => 'test.counting';

  @override
  String get label => 'Count';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() async {
    attempts++;
    await runOperation(TaskOperation<void>((op) async => runs++), message: 'Working…');
  }
}

void main() {
  test('окно перерисовывается не на каждый файл', () async {
    final command = _ProbeCommand();
    var notifications = 0;
    command.addListener(() => notifications++);

    await command.run(
      TaskOperation<void>((op) async {
        for (var i = 0; i < 500; i++) {
          op.report(OperationProgress(message: 'file$i.txt', processed: i, total: 500));
        }
      }),
    );

    // Пятьсот файлов — не пятьсот кадров: сообщения приходят все, а перерисовки
    // ограничены по времени.
    expect(notifications, lessThan(20));
  });

  test('последнее состояние всё равно доходит', () async {
    final command = _ProbeCommand();

    await command.run(
      TaskOperation<void>((op) async {
        for (var i = 0; i < 20; i++) {
          op.report(OperationProgress(message: 'file$i.txt', processed: i, total: 20));
          // Пауза больше интервала перерисовки: события не сливаются в одно.
          await Future<void>.delayed(const Duration(milliseconds: 6));
        }
        op.report(const OperationProgress(percent: 1, message: 'Done', processed: 20, total: 20));
      }),
    );

    expect(command.isRunning, isFalse);
    expect(command.processed, 20);
    expect(command.total, 20);
    expect(command.totalIsFinal, isTrue);
  });

  test('пока считают, общее количество не выдаётся за окончательное', () async {
    final command = _ProbeCommand();
    final operation = TaskOperation<void>((op) async {
      op.report(const OperationProgress(message: 'a.txt', processed: 1, total: 3, totalIsFinal: false));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });

    final running = command.run(operation);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(command.processed, 1);
    expect(command.total, 3);
    expect(command.totalIsFinal, isFalse);
    expect(command.progress, closeTo(1 / 3, 0.001));

    await running;
  });

  group('завершение прогона', () {
    test('дожидается конца работы', () async {
      final command = _ProbeCommand();

      await command.run(TaskOperation<void>((op) async {}));

      await expectLater(command.completion, completes);
    });

    test('дожидается и отменённой работы', () async {
      final command = _ProbeCommand();

      final operation = TaskOperation<void>((op) async {
        // Работа встаёт до отмены: без неё прогон закончился бы сам собой.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await op.checkpoint();
      });

      final run = command.run(operation);
      operation.cancel();
      await run;

      // Раньше completion завершалось только в submit(), и ждущий отменённой
      // работы не дожидался её никогда.
      await expectLater(command.completion, completes);
    });
  });

  group('фаза прогона', () {
    test('работа не начиналась — прогон в idle', () {
      final command = _ProbeCommand();

      expect(command.phase, CommandRunPhase.idle);
      expect(command.isBusy, isFalse);
      expect(command.isRunning, isFalse);
    });

    test('операция кончилась, а прогон — ещё нет', () async {
      final command = _ProbeCommand();

      await command.run(TaskOperation<void>((op) async {}));

      // Между этими двумя ответами лежит хвост работы: отпустить аренду,
      // перечитать панели, закрыть окно. Пока это был один признак занятости,
      // окно в хвосте откатывалось к форме с параметрами.
      expect(command.isRunning, isFalse);
      expect(command.isBusy, isTrue);
      expect(command.phase, CommandRunPhase.done);
    });

    test('отменённая работа оставляет тот же исход', () async {
      final command = _ProbeCommand();
      final operation = TaskOperation<void>((op) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await op.checkpoint();
      });

      final run = command.run(operation);
      operation.cancel();
      await run;

      // Отмена — такой же конец прогона, как успех: окно закрывается тем же
      // путём и точно так же не должно мигать формой.
      expect(command.phase, CommandRunPhase.done);
    });

    test('подтверждение в хвосте работы не запускает её второй раз', () async {
      final command = _CountingCommand();

      await command.submit();
      expect(command.attempts, 1);
      expect(command.runs, 1);

      // Хвост: операции уже нет, окно ещё есть, и Enter уходит в submit.
      // Пока охрана смотрела на идущую операцию, он запускал работу заново.
      await command.submit();

      expect(command.attempts, 1);
      expect(command.runs, 1);
    });
  });
}
