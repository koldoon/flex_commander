import '../../async/operation_request.dart';

/// Ответы на препятствие по ходу переноса: имя занято, объект не читается,
/// ссылку не сохранить.
///
/// Словарь **движка переноса**, а не всех вопросов вообще: «перезаписать» и
/// «пропустить все» имеют смысл ровно там, где работа идёт по многим объектам
/// и на каждом может споткнуться. Лежит поэтому рядом с движком, а не в общем
/// типе варианта ответа ([OperationRequestOption]).
///
/// Пользуется им и тот, кто движком не пользуется: упаковка в архив спотыкается
/// о те же препятствия и обязана спрашивать теми же словами. Это не заимствование
/// чужого, а тот же самый протокол — «работа по многим объектам наткнулась на
/// один плохой».
abstract final class TransferAnswers {
  /// Заменить то, что уже лежит на месте.
  static const overwrite = OperationRequestOption('overwrite', 'Overwrite');

  /// Заменять дальше, не спрашивая.
  static const overwriteAll = OperationRequestOption('overwriteAll', 'Overwrite all');

  /// Оставить как есть и перейти к следующему.
  static const skip = OperationRequestOption('skip', 'Skip');

  /// Пропускать дальше, не спрашивая.
  static const skipAll = OperationRequestOption('skipAll', 'Skip all');

  /// Начать работу, о цене которой предупредили.
  static const proceed = OperationRequestOption('proceed', 'Proceed');

  /// Повторить то, что не вышло с первого раза, — например отправку архива,
  /// оборвавшуюся посреди сети.
  static const retry = OperationRequestOption('retry', 'Retry');

  /// Бросить работу целиком.
  ///
  /// Не то же, что [CancelAnswers.abort]: там прерывают работу по своей воле,
  /// здесь — упёршись в препятствие, и кнопка стоит рядом с «пропустить».
  static const cancel = OperationRequestOption('cancel', 'Cancel');
}
