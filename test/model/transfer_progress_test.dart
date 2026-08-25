import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Счёт объектов идёт двумя встречными потоками: обработанные растут по мере
/// работы, общее число — по мере фонового подсчёта. Здесь проверяется, что они
/// сходятся, в каком бы порядке ни шли события.
void main() {
  late List<OperationProgress> reports;
  late TaskOperation<void, void> operation;
  late TransferProgress progress;

  /// Часы, которые двигает тест: скорость и оценка времени иначе зависели бы
  /// от того, как быстро сегодня работает машина.
  late DateTime now;
  void tick(Duration step) => now = now.add(step);

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    reports = [];
    // Тело операции не завершается: важна только отчётность.
    operation = startedTask<void>((op) async {
      await Future<void>.delayed(const Duration(seconds: 10));
    });
    // Отмена в конце теста завершает операцию ошибкой, и прочитать её некому.
    operation.result.ignore();
    operation.progress.listen(reports.add);
    progress = TransferProgress(operation, 'Copying', clock: () => now);
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
      progress.countOne(0);
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
    progress.countOne(0);
    progress.startSource('a.txt');
    await flush();

    expect(reports.last.total, 1);
    expect(reports.last.totalIsFinal, isFalse);
  });

  test('доля не выходит за единицу, если работа обогнала подсчёт', () async {
    progress.countOne(0);
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
        progress.countOne(0);
      }
      progress.sourceCounted(index, count, 0);
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

  test('после остановки фоновый подсчёт больше ничего не приписывает', () async {
    progress.countOne(100);
    progress.countingFinished();
    await flush();
    final counted = reports.last.total;

    progress.stop();
    progress.countOne(100);
    progress.sourceCounted(1, 5, 500);
    await flush();

    // Досчитывать после конца работы нечего: числа остались теми же.
    expect(reports.last.total, counted);
    expect(reports.last.totalBytes, 100);
  });

  test('после остановки о последнем плече рассказать всё ещё можно', () async {
    // Останавливается подсчёт, а не рассказ: за записью в архив идёт его
    // пересборка, и молчать о ней нельзя — окно замерло бы на «готово», пока
    // работа идёт.
    progress.stop();
    progress.beginStage('repacking archive', index: 2, count: 2, sized: false);
    await flush();

    expect(reports.last.stageName, 'repacking archive');
    expect(reports.last.hasStages, isTrue);
    expect(reports.last.percent, isNull, reason: 'сколько осталось — неизвестно');
  });

  group('байты', () {
    test('доля считается по байтам, а не по объектам', () async {
      // Один файл на сто байт: по объектам это «0 из 1» до самого конца.
      progress.countOne(100);
      progress.countingFinished();
      progress.advanceBytes(40);
      await flush();

      expect(reports.last.processed, 0);
      expect(reports.last.percent, 0.4);
      expect(reports.last.bytes, 40);
      expect(reports.last.totalBytes, 100);
    });

    test('без байтов доля остаётся по объектам', () async {
      // Удаление в корзину объёма не переносит — считать нечего.
      progress.countOne(0);
      progress.countOne(0);
      progress.countingFinished();
      progress.advance('a.txt');
      await flush();

      expect(reports.last.totalBytes, isNull);
      expect(reports.last.percent, 0.5);
    });

    test('источник, обработанный целиком, засчитывает и байты', () async {
      progress.countOne(70);
      progress.countOne(30);
      progress.sourceCounted(0, 2, 100);
      progress.sourceDoneWholly(0);
      await flush();

      // Переименование перенесло поддерево разом: объём тоже сделан целиком.
      expect(reports.last.bytes, 100);
      expect(reports.last.percent, 1);
    });

    test('скорость появляется не раньше второго отсчёта', () async {
      progress.countOne(1000);
      progress.advanceBytes(100);
      await flush();
      expect(reports.last.bytesPerSecond, isNull);

      tick(const Duration(seconds: 1));
      progress.advanceBytes(100);
      await flush();

      // Двести байт за секунду — но первый отсчёт был на сотне.
      expect(reports.last.bytesPerSecond, 100);
    });

    test('оценка времени считается из скорости и остатка', () async {
      progress.countOne(1000);
      progress.advanceBytes(100);
      tick(const Duration(seconds: 1));
      progress.advanceBytes(100);
      await flush();

      // Осталось восемьсот байт при сотне в секунду.
      expect(reports.last.remaining, const Duration(seconds: 8));
    });

    test('пока скорости нет, времени не обещаем', () async {
      progress.countOne(1000);
      progress.advanceBytes(100);
      await flush();

      expect(reports.last.remaining, isNull);
    });

    test('частые куски не сбивают счёт скорости', () async {
      progress.countOne(1000);
      // Куски идут чаще, чем берутся отсчёты: сотня измерений подряд не должна
      // превратиться в бесконечную скорость.
      for (var i = 0; i < 100; i++) {
        progress.advanceBytes(1);
      }
      tick(const Duration(seconds: 1));
      progress.advanceBytes(100);
      await flush();

      expect(reports.last.bytes, 200);
      expect(reports.last.bytesPerSecond, isNotNull);
      expect(reports.last.bytesPerSecond, greaterThan(0));
    });
  });
}
