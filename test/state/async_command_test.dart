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
}
