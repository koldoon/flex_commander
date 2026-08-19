import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ход работы, у которой два плеча: сперва читаем исходное, потом отдаём
/// готовое. Второе плечо появляется в счёте не сразу — его размер до времени
/// неизвестен.
void main() {
  test('работа прирастает байтами без нового объекта', () async {
    final reports = <OperationProgress>[];

    final operation = TaskOperation<void>((op) async {
      final progress = TransferProgress(op, 'Packing');

      // Первое плечо: два объекта на 200 байт, пройдены целиком.
      progress
        ..countOne(100)
        ..countOne(100)
        ..advanceBytes(200);
      // Пауза не для красоты: сообщения уходят потоком, и без неё они не
      // успевают дойти до слушателя — работа кончится раньше.
      await Future<void>.delayed(Duration.zero);

      // Второе плечо: работы прибавилось, а объектов — нет.
      progress.countBytes(50);
      await Future<void>.delayed(Duration.zero);

      progress.advanceBytes(50);
      await Future<void>.delayed(Duration.zero);
    });

    operation.progress.listen(reports.add);
    await operation.result;

    // Ни одного лишнего объекта: приросли только байты.
    expect(reports.map((report) => report.total), everyElement(lessThanOrEqualTo(2)));

    // Пока о втором плече не знали, первое выглядело законченным.
    final firstLegDone = reports.firstWhere((report) => report.bytes == 200 && report.totalBytes == 200);
    expect(firstLegDone.percent, 1);

    // Как только оно объявлено, доля пересчиталась — назад бар при этом
    // не поехал: сделанное осталось сделанным.
    final secondLegKnown = reports.firstWhere((report) => report.totalBytes == 250);
    expect(secondLegKnown.percent, closeTo(0.8, 0.001));
    expect(secondLegKnown.bytes, 200);

    expect(reports.last.percent, 1);
  });

  test('у текущего объекта свой счёт, и он обнуляется на следующем', () async {
    final reports = <OperationProgress>[];

    final operation = TaskOperation<void>((op) async {
      final progress = TransferProgress(op, 'Copying');
      progress
        ..countOne(100)
        ..countOne(100)
        ..startItem('first.bin', bytes: 100);
      await Future<void>.delayed(Duration.zero);

      // Половина файла: общий счёт сдвинулся на четверть, а по файлу — половина.
      progress.advanceBytes(50);
      await Future<void>.delayed(Duration.zero);
      final half = reports.last;
      expect(half.itemName, 'first.bin');
      expect(half.itemPercent, 0.5);
      expect(half.percent, 0.25);

      progress
        ..advanceBytes(50)
        ..advance('first.bin');
      await Future<void>.delayed(Duration.zero);

      // Объект пройден: его счёт больше ничего не значит и не должен
      // притворяться ходом следующего.
      final done = reports.last;
      expect(done.itemName, isEmpty);
      expect(done.itemPercent, isNull);
      expect(done.percent, 0.5);

      progress.startItem('second.bin', bytes: 100);
      await Future<void>.delayed(Duration.zero);
      expect(reports.last.itemPercent, 0);
    });

    operation.progress.listen(reports.add);
    await operation.result;
  });

  test('объект без известного размера показывать нечем', () async {
    final reports = <OperationProgress>[];

    final operation = TaskOperation<void>((op) async {
      final progress = TransferProgress(op, 'Deleting');
      // Размер бывает неизвестен: удаление в корзину, источник без размеров.
      progress.startItem('unknown.bin');
      await Future<void>.delayed(Duration.zero);
    });

    operation.progress.listen(reports.add);
    await operation.result;

    expect(reports.last.itemName, 'unknown.bin');
    expect(reports.last.itemPercent, isNull);
  });
}
