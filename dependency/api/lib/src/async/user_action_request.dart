import 'dart:async';

/// Вариант ответа на [ChoiceRequest].
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

/// То, из-за чего работа встала и ждёт человека.
///
/// Сам по себе — только **сигнал**: ни текста, ни полей, ни вариантов ответа
/// здесь нет. Всё это лежит в подтипе, который заводит тот, кто спрашивает, и
/// для которого он же регистрирует вид. Так архиватор спросит пароль формой из
/// двух полей, а движок переноса — конфликтом с датами и размерами обоих
/// файлов, и ядру не нужно знать ни про то, ни про другое.
abstract interface class UserActionRequest {}

/// Готовая заявка для простого вопроса: сообщение и кнопки.
///
/// Вид для неё рисует ядро, поэтому свой заводить не надо: перезаписать,
/// пропустить, повторить, прервать — всё это кнопки и строка.
class ChoiceRequest implements UserActionRequest {
  ChoiceRequest({
    required this.message,
    required this.options,
    required this.enterOption,
    this.escapeOption,
    this.inputLabel,
    this.secret = false,
  }) : assert(options.isNotEmpty, 'Нужен хотя бы один вариант ответа');

  final String message;
  final List<OperationOption> options;

  /// Какую кнопку подсветить и нажать по Enter. У конфликта имён это Skip:
  /// молча затирать чужие файлы нельзя.
  ///
  /// Обязательный, а не «последний по умолчанию»: забыть его — ровно тот
  /// способ, которым однажды затрут чужие файлы. Это только про Enter — что
  /// делать, если не ответили вовсе, решает сама работа.
  final OperationOption enterOption;

  /// Что означает Esc; null — ничего, и вопрос придётся закрыть кнопкой.
  ///
  /// Отдельно от [enterOption], потому что совпадают они не всегда: у вопроса
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
  String toString() => 'ChoiceRequest($message)';
}
