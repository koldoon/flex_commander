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

  /// Прервать работу целиком — ответ на подтверждение отмены.
  static const abort = OperationOption('abort', 'Abort');

  /// Продолжить работу: отменяется не операция, а сам вопрос о её отмене.
  ///
  /// Подпись поэтому «Cancel» — пользователь отказывается от прерывания, — а
  /// идентификатор `resume`: в коде «cancel» уже значит «прервать операцию»,
  /// и второе значение того же слова читалось бы наоборот.
  static const resume = OperationOption('resume', 'Cancel');

  @override
  String toString() => 'OperationOption($id)';
}

/// Вопрос пользователю из середины операции: перезаписать файл, пропустить
/// недоступный каталог, повторить попытку. Операция ждёт [answer] и продолжает
/// работу с полученным вариантом.
class OperationRequest {
  OperationRequest({
    required this.message,
    required this.options,
    OperationOption? defaultOption,
    this.escapeOption,
    this.inputLabel,
    this.secret = false,
  }) : assert(options.isNotEmpty, 'Нужен хотя бы один вариант ответа'),
       defaultOption = defaultOption ?? options.last;

  final String message;
  final List<OperationOption> options;

  /// Вариант, который применяется, если вопрос никто не слушает. Он же
  /// отвечает на Enter: «вариант по умолчанию» — это одно и то же.
  final OperationOption defaultOption;

  /// Что означает Esc; null — ничего, и вопрос придётся закрыть кнопкой.
  ///
  /// Отдельно от [defaultOption], потому что совпадают они не всегда: у вопроса
  /// «прервать работу?» Enter прерывает, а Esc — отказывается прерывать.
  final OperationOption? escapeOption;

  /// Подпись поля ввода; null — вопрос только из кнопок.
  ///
  /// Так спрашивают пароль и всё, чего кнопками не выразить: вариантов ответа
  /// бесконечно много. Кнопки при этом остаются — ими отвечают «отменить».
  final String? inputLabel;

  /// Набранное не показывать: пароль.
  final bool secret;

  /// Что ввели. Пусто у вопроса без поля и пока на него не ответили.
  String get text => _text;
  String _text = '';

  final Completer<OperationOption> _answer = Completer<OperationOption>();

  Future<OperationOption> get answer => _answer.future;

  bool get isAnswered => _answer.isCompleted;

  /// Отвечает на вопрос. [text] — набранное, если у вопроса было поле ввода.
  void respond(OperationOption option, {String text = ''}) {
    if (_answer.isCompleted) {
      return;
    }
    // Записывается до ответа: тот, кто ждёт `answer`, читает `text` сразу же.
    _text = text;
    _answer.complete(option);
  }

  @override
  String toString() => 'OperationRequest($message)';
}
