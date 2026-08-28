import 'package:fc_api/fc_api.dart';

/// Работа, которой на самом деле нет.
///
/// Провайдеру, пересобирающему архив, нужна не вся операция, а три вещи:
/// сказать о ходе, спросить человека, проверить отмену. Ровно их тест и
/// подставляет — и заодно видит, о чём спрашивали.
class FakeOperationContext implements OperationContext {
  FakeOperationContext({this.answer});

  /// Чем отвечать на вопросы; null — вариантом по умолчанию (`Enter`).
  final OperationRequestOption? answer;

  /// Что спрашивали, по порядку.
  final List<OperationRequest> asked = [];

  /// Что рассказывали о ходе.
  final List<String> stages = [];

  /// Работу просили прекратить: следующая проверка бросит [OperationCanceled].
  bool canceled = false;

  @override
  void checkCanceled() {
    if (canceled) {
      throw const OperationCanceled();
    }
  }

  @override
  void report({
    String message = '',
    double? percent,
    bool indeterminate = false,
    int bytesTransferred = 0,
    int? bytesTotal,
    String itemName = '',
    int itemBytesTransferred = 0,
    int? itemBytesTotal,
    int stage = 0,
    int stageCount = 0,
    String stageName = '',
  }) {
    if (stageName.isNotEmpty) {
      stages.add(stageName);
    }
  }

  @override
  Future<OperationRequestOption> ask(OperationRequest request) async {
    asked.add(request);
    return answer ?? request.enterOption;
  }
}
