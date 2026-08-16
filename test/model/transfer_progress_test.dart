import 'package:flex_commander/model/async/async_operation.dart';
import 'package:flex_commander/model/async/transfer_progress.dart';
import 'package:flutter_test/flutter_test.dart';

/// Счёт объектов идёт двумя встречными потоками: обработанные растут по мере
/// работы, общее число — по мере фонового подсчёта. Здесь проверяется, что они
/// сходятся, в каком бы порядке ни шли события.
void main() {
  late List<OperationProgress> reports;
  late TaskOperation<void> operation;
  late TransferProgress progress;

  setUp(() {
    reports = [];
    // Тело операции не завершается: важна только отчётность.
    operation = TaskOperation<void>((op) async {
      await Future<void>.delayed(const Duration(seconds: 10));
    });
    // Отмена в конце теста завершает операцию ошибкой, и прочитать её некому.
    operation.result.ignore();
    operation.progress.listen(reports.add);
    progress = TransferProgress(operation, 'Copying');
  });

  tearDown(() => operation.cancel());

  /// Ждёт, пока сообщение о ходе работы дойдёт до подписчика.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('доля неизвестна, пока ничего не посчитано', () async {
    progress.startSource('notes.txt');
    await flush();

    expect(reports.last.total, isNull);
    expect(reports.last.percent, isNull);
    expect(reports.last.message, 'Copying notes.txt…');
  });

  test('доля считается из обработанных и общего', () async {
    for (var i = 0; i < 4; i++) {
      progress.countOne();
    }
    progress.advance('a.txt');
    progress.countingFinished();
    await flush();

    expect(reports.last.processed, 1);
    expect(reports.last.total, 4);
    expect(reports.last.percent, 0.25);
    expect(reports.last.totalIsFinal, isTrue);
  });

  test('пока подсчёт идёт, общее число не считается окончательным', () async {
    progress.countOne();
    progress.startSource('a.txt');
    await flush();

    expect(reports.last.total, 1);
    expect(reports.last.totalIsFinal, isFalse);
  });

  test('доля не выходит за единицу, если работа обогнала подсчёт', () async {
    progress.countOne();
    progress.advance('a.txt');
    progress.advance('b.txt');
    progress.startSource('c.txt');
    await flush();

    expect(reports.last.percent, 1);
  });

  group('источник, обработанный целиком', () {
    /// Подсчёт идёт поштучно, поэтому итог по источнику приходит после его
    /// объектов — как и на настоящей файловой системе.
    void countSource(int index, int count) {
      for (var i = 0; i < count; i++) {
        progress.countOne();
      }
      progress.sourceCounted(index, count);
    }

    test('учитывается сразу, если его уже посчитали', () async {
      countSource(0, 50);
      progress.sourceDoneWholly(0);
      progress.startSource('next');
      await flush();

      expect(reports.last.processed, 50);
    });

    test('учитывается позже, если подсчёт до него ещё не дошёл', () async {
      // Переименование каталога успело раньше, чем его обошёл счётчик.
      progress.sourceDoneWholly(0);
      progress.startSource('next');
      await flush();
      expect(reports.last.processed, 0);

      countSource(0, 50);
      progress.countingFinished();
      await flush();

      expect(reports.last.processed, 50);
      expect(reports.last.percent, 1);
    });
  });

  test('сообщается каждое изменение: как часто перерисовываться, решает окно', () async {
    for (var i = 0; i < 100; i++) {
      progress.advance('file$i.txt');
    }
    await flush();

    expect(reports.length, 100);
    expect(reports.last.message, 'Copying file99.txt…');
  });

  test('в конце счётчики сходятся, даже если подсчёт не успел', () async {
    // Каталог перенесён переименованием, а обойти его счётчик не успел.
    progress.sourceDoneWholly(0);
    progress.stop();
    progress.finish();
    await flush();

    expect(reports.last.percent, 1);
    expect(reports.last.processed, reports.last.total);
  });

  test('после остановки фоновый подсчёт знает, что пора закончить', () {
    expect(progress.stopped, isFalse);
    progress.stop();
    expect(progress.stopped, isTrue);
  });
}
