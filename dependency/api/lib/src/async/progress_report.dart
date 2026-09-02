import 'operation_status.dart';

/// Ход дела значением — то, что работа рассказывает о себе через границу.
///
/// **Целиком, поле в поле.** Возить одно сообщение и число объектов уже
/// пробовали: окно копирования осталось без объёма, скорости, имени файла и
/// второй полосы. Отчёт маленький — полтора десятка чисел, — и жалеть на него
/// нечего (`docs/spec/client-server.md`, §11, урок 15).
class ProgressReport {
  const ProgressReport({
    this.state = OperationState.processing,
    this.message = '',
    this.percent,
    this.indeterminate = false,
    this.itemsTransferred = 0,
    this.itemsTotal,
    this.totalIsFinal = true,
    this.bytesTransferred = 0,
    this.bytesTotal,
    this.speed,
    this.itemName = '',
    this.itemBytesTransferred = 0,
    this.itemBytesTotal,
    this.stage = 0,
    this.stageCount = 0,
    this.stageName = '',
  });

  final OperationState state;
  final String message;
  final double? percent;
  final bool indeterminate;

  final int itemsTransferred;
  final int? itemsTotal;
  final bool totalIsFinal;

  final int bytesTransferred;
  final int? bytesTotal;
  final double? speed;

  final String itemName;
  final int itemBytesTransferred;
  final int? itemBytesTotal;

  final int stage;
  final int stageCount;
  final String stageName;

  @override
  String toString() => 'ProgressReport(${state.name}, $message)';
}
