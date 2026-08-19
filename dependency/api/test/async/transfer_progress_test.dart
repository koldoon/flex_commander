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
}
