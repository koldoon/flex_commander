import 'dart:async';

/// Вариант ответа на [OperationRequest].
class OperationOption {
  const OperationOption(this.id, this.label);

  /// Идентификатор для кода: 'overwrite', 'skip', 'skipAll', 'cancel'.
  final String id;

  /// Подпись кнопки в диалоге.
  final String label;

  static const overwrite = OperationOption('overwrite', 'Overwrite');
  static const overwriteAll = OperationOption('overwriteAll', 'Overwrite all');
  static const skip = OperationOption('skip', 'Skip');
  static const skipAll = OperationOption('skipAll', 'Skip all');
  static const retry = OperationOption('retry', 'Retry');
  static const cancel = OperationOption('cancel', 'Cancel');

  @override
  String toString() => 'OperationOption($id)';
}

/// Вопрос пользователю из середины операции: перезаписать файл, пропустить
/// недоступный каталог, повторить попытку. Операция ждёт [answer] и продолжает
/// работу с полученным вариантом.
class OperationRequest {
  OperationRequest({required this.message, required this.options, OperationOption? defaultOption})
    : assert(options.isNotEmpty, 'Нужен хотя бы один вариант ответа'),
      defaultOption = defaultOption ?? options.last;

  final String message;
  final List<OperationOption> options;

  /// Вариант, который применяется, если вопрос никто не слушает.
  final OperationOption defaultOption;

  final Completer<OperationOption> _answer = Completer<OperationOption>();

  Future<OperationOption> get answer => _answer.future;

  bool get isAnswered => _answer.isCompleted;

  void respond(OperationOption option) {
    if (!_answer.isCompleted) {
      _answer.complete(option);
    }
  }

  @override
  String toString() => 'OperationRequest($message)';
}
