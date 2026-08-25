import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ход работы, у которой два плеча: сперва читаем исходное, потом отдаём
/// готовое. Второе плечо появляется в счёте не сразу — его размер до времени
/// неизвестен.
void main() {
  test('работа прирастает байтами без нового объекта', () async {
    late final _Log reports;

    final operation = TaskOperation<void, void>((op, _) async {
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
    reports = _Log(operation.status);
    operation.start(null);
    await operation.result;

    // Ни одного лишнего объекта: приросли только байты.
    expect(reports.map((report) => report.itemsTotal), everyElement(lessThanOrEqualTo(2)));

    // Пока о втором плече не знали, первое выглядело законченным.
    final firstLegDone = reports.firstWhere((report) => report.bytesTransferred == 200 && report.bytesTotal == 200);
    expect(firstLegDone.percent, 1);

    // Как только оно объявлено, доля пересчиталась — назад бар при этом
    // не поехал: сделанное осталось сделанным.
    final secondLegKnown = reports.firstWhere((report) => report.bytesTotal == 250);
    expect(secondLegKnown.percent, closeTo(0.8, 0.001));
    expect(secondLegKnown.bytesTransferred, 200);

    expect(reports.last.percent, 1);
  });

  test('у текущего объекта свой счёт, и он обнуляется на следующем', () async {
    late final _Log reports;

    final operation = TaskOperation<void, void>((op, _) async {
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

      // Объект пройден. На полосе он остаётся доделанным, а не исчезает:
      // пустое имя в отчёте значит «сказать нечего», а не «объекта не было», —
      // иначе полоса мигала бы в конце каждого файла.
      final done = reports.last;
      expect(done.itemName, 'first.bin');
      expect(done.itemPercent, 1);
      expect(done.percent, 0.5);

      // А вот ходом следующего он не притворяется: счёт начинается заново.
      progress.startItem('second.bin', bytes: 100);
      await Future<void>.delayed(Duration.zero);
      expect(reports.last.itemName, 'second.bin');
      expect(reports.last.itemPercent, 0);
    });
    reports = _Log(operation.status);
    operation.start(null);
    await operation.result;
  });

  test('объект без известного размера показывать нечем', () async {
    late final _Log reports;

    final operation = TaskOperation<void, void>((op, _) async {
      final progress = TransferProgress(op, 'Deleting');
      // Размер бывает неизвестен: удаление в корзину, источник без размеров.
      progress.startItem('unknown.bin');
      await Future<void>.delayed(Duration.zero);
    });
    reports = _Log(operation.status);
    operation.start(null);
    await operation.result;

    expect(reports.last.itemName, 'unknown.bin');
    expect(reports.last.itemPercent, isNull);
  });
}

/// Ход работы по шагам, снятый с её статуса.
///
/// Свой, а не `ProgressLog` из `fc_test_kit`: тот зависит от `fc_api`, и
/// обратная зависимость замкнула бы круг. Заводится **до** запуска — после него
/// первые шаги уже случились бы.
class _Log {
  _Log(this.status) {
    status.addListener(_record);
  }

  final OperationStatus status;
  final List<_Step> steps = [];

  _Step get last => steps.last;

  Iterable<T> map<T>(T Function(_Step step) toElement) => steps.map(toElement);

  _Step firstWhere(bool Function(_Step step) test) => steps.firstWhere(test);

  void _record() {
    final transfer = status as MultipleTransferOperationStatus;
    final item = status as SingleTransferOperationStatus;
    final step = _Step(
      itemsTotal: transfer.itemsTotal,
      bytesTransferred: transfer.bytesTransferred,
      bytesTotal: transfer.bytesTotal,
      percent: transfer.percentProgress,
      itemName: item.itemName,
      itemBytesTransferred: item.itemBytesTransferred,
      itemBytesTotal: item.itemBytesTotal,
    );
    // Пустые не пишутся: смена состояния — это уведомление о том же самом
    // ходе дела, и шагом работы она не была.
    if (step.isEmpty || (steps.isNotEmpty && steps.last == step)) {
      return;
    }
    steps.add(step);
  }
}

class _Step {
  const _Step({
    required this.itemsTotal,
    required this.bytesTransferred,
    required this.bytesTotal,
    required this.percent,
    required this.itemName,
    required this.itemBytesTransferred,
    required this.itemBytesTotal,
  });

  final int? itemsTotal;
  final int bytesTransferred;
  final int? bytesTotal;
  final double? percent;
  final String itemName;
  final int itemBytesTransferred;
  final int? itemBytesTotal;

  /// Работа ещё ничего о себе не сказала.
  bool get isEmpty => itemsTotal == null && bytesTransferred == 0 && percent == null && itemName.isEmpty;

  /// Доля текущего объекта; null — размер неизвестен, показывать нечем.
  double? get itemPercent {
    final size = itemBytesTotal;
    return size == null || size <= 0 ? null : itemBytesTransferred / size;
  }

  @override
  bool operator ==(Object other) =>
      other is _Step &&
      itemsTotal == other.itemsTotal &&
      bytesTransferred == other.bytesTransferred &&
      bytesTotal == other.bytesTotal &&
      percent == other.percent &&
      itemName == other.itemName &&
      itemBytesTransferred == other.itemBytesTransferred &&
      itemBytesTotal == other.itemBytesTotal;

  @override
  int get hashCode =>
      Object.hash(itemsTotal, bytesTransferred, bytesTotal, percent, itemName, itemBytesTransferred, itemBytesTotal);
}
