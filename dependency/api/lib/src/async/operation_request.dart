import 'dart:async';

/// Вариант ответа на [OperationRequest].
class OperationRequestOption {
  const OperationRequestOption(this.id, this.label);

  /// Идентификатор для кода: 'overwrite', 'skip', 'skipAll', 'cancel'.
  final String id;

  /// Подпись кнопки в диалоге.
  final String label;

  static const overwrite = OperationRequestOption('overwrite', 'Overwrite');
  static const overwriteAll = OperationRequestOption('overwriteAll', 'Overwrite all');
  static const skip = OperationRequestOption('skip', 'Skip');
  static const skipAll = OperationRequestOption('skipAll', 'Skip all');
  static const retry = OperationRequestOption('retry', 'Retry');
  static const cancel = OperationRequestOption('cancel', 'Cancel');

  /// Прервать работу целиком — ответ на подтверждение отмены.
  static const abort = OperationRequestOption('abort', 'Abort');

  /// Продолжить работу: отменяется не операция, а сам вопрос о её отмене.
  ///
  /// Подпись поэтому «Cancel» — пользователь отказывается от прерывания, — а
  /// идентификатор `resume`: в коде «cancel» уже значит «прервать операцию»,
  /// и второе значение того же слова читалось бы наоборот.
  static const resume = OperationRequestOption('resume', 'Cancel');

  @override
  String toString() => 'OperationRequestOption($id)';
}

/// Работа встала и ждёт человека.
///
/// Только **сигнал**: ни текста, ни полей, ни вариантов ответа здесь нет.
/// Чем именно спрашивать — дело подтипа, который заводит тот, кто спрашивает,
/// и для которого он же регистрирует вид. Ядру знать про это не нужно: оно
/// лишь поднимает окно, найдя вид по типу заявки.
///
/// Отсюда и разные подтипы под разные вопросы: [OperationRequest] — сообщение
/// и кнопки, `CredentialsRequest` — форма из имени и пароля с памятью по
/// `realm`. Свести их к одному типу не выходит, а показывать их обязан кто
/// угодно, не зная, чья это работа: пароль к архиву спрашивает архиватор, а
/// ждёт чтения каталога панель.
abstract interface class UserActionRequest {}

/// Вопрос по ходу работы: сообщение и кнопки.
///
/// Самый частый вид заявки, поэтому вид для неё рисует ядро и свой заводить не
/// надо: перезаписать, пропустить, повторить, прервать — всё это строка и
/// набор кнопок. Всё, что в них не укладывается, заводит свой подтип
/// [UserActionRequest].
class OperationRequest implements UserActionRequest {
  OperationRequest({
    required this.message,
    required this.options,
    required this.enterOption,
    this.escapeOption,
    this.inputLabel,
    this.secret = false,
  }) : assert(options.isNotEmpty, 'Нужен хотя бы один вариант ответа');

  final String message;
  final List<OperationRequestOption> options;

  /// Какую кнопку подсветить и нажать по Enter. У конфликта имён это Skip:
  /// молча затирать чужие файлы нельзя.
  ///
  /// Обязательный, а не «последний по умолчанию»: забыть его — ровно тот
  /// способ, которым однажды затрут чужие файлы. Это только про Enter — что
  /// делать, если не ответили вовсе, решает сама работа.
  final OperationRequestOption enterOption;

  /// Что означает Esc; null — ничего, и вопрос придётся закрыть кнопкой.
  ///
  /// Отдельно от [enterOption], потому что совпадают они не всегда: у вопроса
  /// «прервать работу?» Enter прерывает, а Esc — отказывается прерывать.
  final OperationRequestOption? escapeOption;

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

  final Completer<OperationRequestOption> _answer = Completer<OperationRequestOption>();

  Future<OperationRequestOption> get answer => _answer.future;

  bool get isAnswered => _answer.isCompleted;

  /// Отвечает на вопрос. [text] — набранное, если у вопроса было поле ввода.
  void respond(OperationRequestOption option, {String text = ''}) {
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
