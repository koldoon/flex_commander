import 'package:fc_api/fc_api.dart';

/// Снимок хода работы: что о ней было известно в один из моментов.
///
/// Имена — из решётки статусов, а не из старого отчёта: `itemsTransferred`
/// вместо `processed`, `bytesTransferred` вместо `bytes`. Это те же имена,
/// какими ход работы читает окно.
class ProgressSnapshot {
  const ProgressSnapshot({
    this.message = '',
    this.percent,
    this.itemsTransferred = 0,
    this.itemsTotal,
    this.totalIsFinal = true,
    this.bytesTransferred = 0,
    this.bytesTotal,
    this.itemName = '',
    this.itemBytesTransferred = 0,
    this.itemBytesTotal,
    this.stageName = '',
    this.stageCount = 0,
    this.speed,
    this.remaining,
  });

  final String message;
  final double? percent;
  final int itemsTransferred;
  final int? itemsTotal;
  final bool totalIsFinal;
  final int bytesTransferred;
  final int? bytesTotal;
  final String itemName;
  final int itemBytesTransferred;
  final int? itemBytesTotal;
  final String stageName;

  /// Сколько плеч у работы; 0 или 1 — работа одноплечая.
  final int stageCount;

  final double? speed;
  final Duration? remaining;

  /// Есть ли о чём говорить: плечи показываются, только когда их больше одного.
  bool get hasStages => stageCount > 1;

  /// Работа ещё ничего о себе не сказала: так выглядит уведомление о смене
  /// состояния, пришедшее раньше первого отчёта.
  bool get isEmpty =>
      message.isEmpty &&
      percent == null &&
      itemsTransferred == 0 &&
      itemsTotal == null &&
      bytesTransferred == 0 &&
      itemName.isEmpty &&
      stageName.isEmpty &&
      stageCount == 0;

  @override
  bool operator ==(Object other) =>
      other is ProgressSnapshot &&
      message == other.message &&
      percent == other.percent &&
      itemsTransferred == other.itemsTransferred &&
      itemsTotal == other.itemsTotal &&
      totalIsFinal == other.totalIsFinal &&
      bytesTransferred == other.bytesTransferred &&
      bytesTotal == other.bytesTotal &&
      itemName == other.itemName &&
      itemBytesTransferred == other.itemBytesTransferred &&
      itemBytesTotal == other.itemBytesTotal &&
      stageName == other.stageName &&
      stageCount == other.stageCount;

  @override
  int get hashCode => Object.hash(
    message,
    percent,
    itemsTransferred,
    itemsTotal,
    totalIsFinal,
    bytesTransferred,
    bytesTotal,
    itemName,
    itemBytesTransferred,
    itemBytesTotal,
    stageName,
    stageCount,
  );

  @override
  String toString() =>
      'ProgressSnapshot($message, $percent, $itemsTransferred/$itemsTotal, $bytesTransferred/$bytesTotal)';
}

/// Ход работы по шагам — для тестов, которым важна не только последняя цифра.
///
/// Раньше это давал поток `progress`; теперь ход держит объект, и журнал
/// снимается с него — так же, как его читает окно. Подписываться надо **до**
/// [Operation.start]: до запуска не происходит ничего, и пропустить нечего.
///
/// Тем, кому нужен только итог, журнал не нужен вовсе: `operation.status`
/// читается напрямую и после конца работы.
class ProgressLog {
  ProgressLog(this.status) {
    status.addListener(_record);
  }

  ProgressLog.of(Operation<Object?, Object?> operation) : this(operation.status);

  final OperationStatus status;

  final List<ProgressSnapshot> reports = [];

  ProgressSnapshot get last => reports.last;

  ProgressSnapshot get first => reports.first;

  void stop() => status.removeListener(_record);

  void _record() {
    final snapshot = _snapshot();
    // Пустые и повторы подряд не пишутся: смена состояния — это уведомление о
    // том же самом ходе дела, и шагом работы она не была.
    if (snapshot.isEmpty || (reports.isNotEmpty && reports.last == snapshot)) {
      return;
    }
    reports.add(snapshot);
  }

  ProgressSnapshot _snapshot() {
    final computable = status is ComputableOperationStatus ? status as ComputableOperationStatus : null;
    final measurable = status is MeasurableOperationStatus ? status as MeasurableOperationStatus : null;
    final single = status is SingleTransferOperationStatus ? status as SingleTransferOperationStatus : null;
    final multiple = status is MultipleTransferOperationStatus ? status as MultipleTransferOperationStatus : null;
    final staged = status is MultistageOperationStatus ? status as MultistageOperationStatus : null;

    return ProgressSnapshot(
      message: status.message,
      percent: computable?.percentProgress,
      itemsTransferred: multiple?.itemsTransferred ?? 0,
      itemsTotal: multiple?.itemsTotal,
      totalIsFinal: multiple?.totalIsFinal ?? true,
      bytesTransferred: multiple?.bytesTransferred ?? 0,
      bytesTotal: multiple?.bytesTotal,
      itemName: single?.itemName ?? '',
      itemBytesTransferred: single?.itemBytesTransferred ?? 0,
      itemBytesTotal: single?.itemBytesTotal,
      stageName: staged?.stages.where((stage) => stage.name.isNotEmpty).lastOrNull?.name ?? '',
      stageCount: staged?.stages.length ?? 0,
      speed: measurable?.speed,
      remaining: measurable?.remaining,
    );
  }
}
