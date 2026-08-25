import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Прогон длительной работы: что он делает с потоком сообщений о ходе дела.
void main() {
  late Application app;

  setUp(() async {
    app = (await testApp(provider: InMemoryTreeProvider([FakeEntry.directory('/home')]))).app;
  });

  /// Прогон без окна: показывать его здесь нечем и незачем — проверяется он сам.
  FcAsyncRun probe() =>
      FcAsyncRun(app: app, commandId: 'test.probe', title: 'Probe', failureMessage: 'Probe failed', show: () {});

  Future<void> work(FcAsyncRun run, Operation<void, void> operation) => run.run(operation, null, message: 'Working…');

  test('окно перерисовывается не на каждый файл', () async {
    final run = probe();
    var notifications = 0;
    run.addListener(() => notifications++);

    await work(
      run,
      TaskOperation<void, void>((op, _) async {
        for (var i = 0; i < 500; i++) {
          op.report(message: 'file$i.txt', itemsTransferred: i, itemsTotal: 500);
        }
      }),
    );

    // Пятьсот файлов — не пятьсот кадров: сообщения приходят все, а перерисовки
    // ограничены по времени.
    expect(notifications, lessThan(20));
  });

  test('последнее состояние всё равно доходит', () async {
    final run = probe();

    await work(
      run,
      TaskOperation<void, void>((op, _) async {
        for (var i = 0; i < 20; i++) {
          op.report(message: 'file$i.txt', itemsTransferred: i, itemsTotal: 20);
          // Пауза больше интервала перерисовки: события не сливаются в одно.
          await Future<void>.delayed(const Duration(milliseconds: 6));
        }
        op.report(percent: 1, message: 'Done', itemsTransferred: 20, itemsTotal: 20);
      }),
    );

    expect(run.isRunning, isFalse);
    expect(run.processed, 20);
    expect(run.total, 20);
    expect(run.totalIsFinal, isTrue);
  });

  test('пока считают, общее количество не выдаётся за окончательное', () async {
    final run = probe();
    final operation = TaskOperation<void, void>((op, _) async {
      op.report(message: 'a.txt', itemsTransferred: 1, itemsTotal: 3, totalIsFinal: false);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });

    final running = work(run, operation);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(run.processed, 1);
    expect(run.total, 3);
    expect(run.totalIsFinal, isFalse);
    expect(run.progress, closeTo(1 / 3, 0.001));

    await running;
  });

  group('завершение прогона', () {
    test('дожидается конца работы', () async {
      final run = probe();

      await work(run, TaskOperation<void, void>((op, _) async {}));

      await expectLater(run.completion, completes);
    });

    test('дожидается и отменённой работы', () async {
      final run = probe();

      final operation = TaskOperation<void, void>((op, _) async {
        // Работа встаёт до отмены: без неё прогон закончился бы сам собой.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await op.checkpoint();
      });

      final running = work(run, operation);
      operation.cancel();
      await running;

      // Раньше completion завершалось только в submit(), и ждущий отменённой
      // работы не дожидался её никогда.
      await expectLater(run.completion, completes);
    });
  });

  group('занятость прогона', () {
    test('работа не начиналась — прогон свободен', () {
      final run = probe();

      expect(run.isBusy, isFalse);
      expect(run.isRunning, isFalse);
    });

    test('операция кончилась, а прогон — ещё нет', () async {
      final run = probe();

      await work(run, TaskOperation<void, void>((op, _) async {}));

      // Между этими двумя ответами лежит хвост работы: отпустить аренду,
      // перечитать панели, закрыть окно. Пока это был один признак занятости,
      // окно в хвосте откатывалось к форме с параметрами.
      expect(run.isRunning, isFalse);
      expect(run.isBusy, isTrue);
    });

    test('отменённая работа оставляет тот же исход', () async {
      final run = probe();
      final operation = TaskOperation<void, void>((op, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await op.checkpoint();
      });

      final running = work(run, operation);
      operation.cancel();
      await running;

      // Отмена — такой же конец прогона, как успех: окно закрывается тем же
      // путём и точно так же не должно мигать формой.
      expect(run.isBusy, isTrue);
    });

    test('подтверждение в хвосте работы не запускает её второй раз', () async {
      final run = probe();
      var attempts = 0;
      var runs = 0;
      run.onStart = () async {
        attempts++;
        await work(run, TaskOperation<void, void>((op, _) async => runs++));
      };

      await run.submit();
      expect(attempts, 1);
      expect(runs, 1);

      // Хвост: операции уже нет, окно ещё есть, и Enter уходит в submit.
      // Пока охрана смотрела на идущую операцию, он запускал работу заново.
      await run.submit();

      expect(attempts, 1);
      expect(runs, 1);
    });
  });
}
