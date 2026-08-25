import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/application.dart';
import '../async/async_operation.dart';
import '../async/operation_request.dart';
import '../async/operation_status.dart';
import '../background/operations.dart';
import '../tree/tree_provider.dart';
import 'app_command.dart';
import '../util/throttle.dart';

/// Прогон длительной работы: то, что живёт, пока открыто её окно.
///
/// Здесь собрано всё, что у таких окон одинаково: подписки на ход работы и на
/// вопросы, признак занятости, ответ на заявку, уход в фон, отмена и
/// завершение. Команде остаётся описать саму работу.
///
/// Живёт в окне, а не в команде: команда показала окно и ушла. Ушедшую в фон
/// работу этот же объект умеет показать снова — он для того и передаёт себя
/// реестру при регистрации.
class FcAsyncRun extends ChangeNotifier implements AsyncCommand {
  FcAsyncRun({
    required this.app,
    required this.commandId,
    required this.title,
    required this.failureMessage,
    required this.show,
  });

  final Application app;

  /// Чьим именем зовётся прогон: из него собирается [runId].
  final String commandId;

  /// Что показать в полоске фоновых работ: «Copy 3 items».
  final String title;

  /// Заголовок разбора, когда работа не удалась: окно показывает его вместо
  /// хода дела.
  ///
  /// Форму назад оно не пускает — правки ввода тут уже ничего не изменят,
  /// работа была начата, — поэтому сказать, что именно не вышло, больше некому.
  final String failureMessage;

  /// Чем показать это окно: и в первый раз, и возвращая из фона.
  final VoidCallback show;

  /// Что делает подтверждение, пока работа не начата: обычно «запустить».
  Future<void> Function()? onStart;

  /// Чем закрыть окно; null — окно ещё не показано.
  VoidCallback? close;

  static var _nextRun = 0;
  late final String runId = '$commandId#${_nextRun++}';

  Operation<Object?, void>? _operation;
  StreamSubscription<OperationRequest>? _requests;
  OperationStatus? _watched;

  /// Что окно показывает, пока работа не заведена: одно сообщение и ничего
  /// больше. Дальше ход берётся у самой работы — второго места ему не нужно.
  String _startingMessage = '';

  OperationRequest? _question;

  /// Вопрос, который показывает окно; null — вопроса нет.
  OperationRequest? get question => _question;

  String? error;

  final Completer<void> _completion = Completer<void>();

  /// Окно перерисовывается не на каждое сообщение операции: копирование мелких
  /// файлов идёт куда быстрее, чем имеет смысл обновлять экран.
  late final Throttle _redraw = Throttle(notifyListeners);

  /// Заводит работу и показывает её ход. Отмена пользователем ошибкой не
  /// считается: сделанное остаётся сделанным.
  ///
  /// Запуск здесь, а не у того, кто работу создал: сперва окно подписывается на
  /// ход дела и на вопросы, и только потом работа начинается. Иначе первый же
  /// вопрос — «перезаписать?» на первом файле — мог бы пройти мимо окна.
  Future<void> run<P>(Operation<P, void> operation, P params, {required String message}) async {
    // По [isBusy], а не по [isRunning]: прогон, который уже кончился,
    // повторять тоже нечего.
    if (isBusy) {
      return;
    }

    _startingMessage = message;
    _operation = operation;
    // Работа заведена: с этого момента её можно найти. В статусной области её
    // пока нет — туда она попадёт, только если её отправят в фон.
    app.operations.register(OperationRun(runId: runId, operation: operation, title: title, bringToFront: show));
    notifyListeners();

    // Сначала подписки, потом запуск: до [Operation.start] не происходит
    // ничего, и потерять нечего.
    _watched = operation.status;
    _watched!.addListener(_onStatusChanged);
    _requests = operation.requests.listen(_onRequest);
    operation.start(params);

    try {
      await operation.result;
    } on OperationCanceled {
      // Прервано пользователем.
    } finally {
      // Подписка снимается, а сам статус остаётся: работа кончилась, но окно
      // ещё открыто, и на её последние цифры смотрят. Забыть их значило бы
      // обнулить полосу в тот момент, когда на неё и смотрят.
      _watched?.removeListener(_onStatusChanged);
      app.operations.forget(runId);
      unawaited(_requests?.cancel());
      _redraw.cancel();
      // Работа остаётся на месте: прогон не кончен, пока не закрыто окно.
      // Иначе оно на весь хвост — отпустить аренду, перечитать панели —
      // откатилось бы к форме с параметрами.
      _question = null;
      _finishRun();
      notifyListeners();
    }
  }

  void _onRequest(OperationRequest request) {
    if (app.operations.byId(runId)?.isInBackground ?? false) {
      // Окно само не выпрыгивает: вырывать человека из другого дела нельзя, а
      // вопрос никуда не денется — работа ждёт столько, сколько нужно. Но и
      // молчать нельзя, иначе она стоит, а он этого не замечает: у полоски в
      // статусной области загорается кнопка, и об этом говорится тостом.
      app.toasts.show('$title: waiting for an answer');
    }
    _question = request;
    notifyListeners();
  }

  void _onStatusChanged() => _redraw();

  /// Что набрано в поле вопроса — если у вопроса есть поле.
  ///
  /// Хранится здесь, а не в виджете: отвечает на вопрос и кнопка, и Enter,
  /// который перехватывает рама окна, — и оба должны видеть одно и то же.
  String _answerText = '';

  void setAnswerText(String value) => _answerText = value;

  /// Ответ на вопрос, заданный по ходу работы.
  void answer(OperationRequestOption option) {
    _question?.respond(option, text: _answerText);
    _question = null;
    _answerText = '';
    notifyListeners();
  }

  /// Убрать окно, оставив работу идти.
  void sendToBackground() {
    app.operations.sendToBackground(runId, owner: app.view.sourceArea);
    close?.call();
  }

  /// Длительную работу можно оставить идти без окна: ход дела она рассказывает
  /// сама, а окна ей нужно ровно столько, сколько нужно человеку.
  ///
  /// Про саму возможность, а не про «идёт ли прямо сейчас»: в хвосте работы
  /// кнопка гаснет, а не исчезает — иначе ряд кнопок дёргался бы под рукой.
  bool get canBackground => true;

  /// Подтверждение: пока идёт вопрос — вариант по умолчанию, иначе запуск.
  Future<void> submit() async {
    final question = _question;
    if (question != null) {
      answer(question.enterOption);
      return;
    }
    if (isBusy) {
      // Работа уже запущена — идёт она или доигрывает, подтверждать нечего.
      // Именно [isBusy]: пока охрана смотрела на идущую операцию, Enter в
      // хвосте работы запускал её второй раз.
      return;
    }

    error = null;
    try {
      await onStart?.call();
    } on FsError catch (failure) {
      error = failure.message;
      notifyListeners();
      return;
    }
    // Ошибка оставляет окно открытым: ввод можно исправить и повторить.
    if (error == null) {
      close?.call();
      _finishRun();
    }
  }

  /// Отказ: пока идёт вопрос — его вариант для Esc; во время работы — просьба
  /// прервать; в остальное время — закрыть окно.
  void dismiss() {
    final question = _question;
    if (question != null) {
      final escape = question.escapeOption;
      if (escape != null) {
        answer(escape);
      }
      // Вопрос без варианта для Esc закрыть нечем: на него надо ответить.
      return;
    }

    if (isRunning) {
      cancel();
      return;
    }
    if (isBusy && error == null) {
      // Работа кончилась и окно закроется само. Закрывать его по Esc раньше
      // нечестно: пропала бы ошибка, если хвост ещё успеет её принести.
      return;
    }
    close?.call();
    _finishRun();
  }

  /// Прервать работу — по кнопке в окне или по Esc.
  ///
  /// Не молча: операция задаст вопрос и **встанет** до ответа. Работа файлового
  /// менеджера необратима, а Esc нажимают не глядя, поэтому цена случайного
  /// нажатия — прерванное копирование посреди дерева.
  @override
  void cancel() {
    if (!isRunning) {
      close?.call();
      return;
    }
    _operation?.requestCancel();
  }

  void _finishRun() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  // --- ход работы ---
  //
  // Читается у самой работы: копию хода окно не держит. Пока работы нет,
  // отвечает то, с чем прогон начинали.

  OperationStatus? get _status => _watched;

  T? _as<T>() {
    final status = _status;
    return status is T ? status as T : null;
  }

  @override
  double? get progress => _as<ComputableOperationStatus>()?.percentProgress;

  @override
  String get progressMessage => _status?.message ?? _startingMessage;

  @override
  int get processed => _as<MultipleTransferOperationStatus>()?.itemsTransferred ?? 0;

  @override
  int? get total => _as<MultipleTransferOperationStatus>()?.itemsTotal;

  @override
  bool get totalIsFinal => _as<MultipleTransferOperationStatus>()?.totalIsFinal ?? true;

  @override
  int get bytes => _as<MultipleTransferOperationStatus>()?.bytesTransferred ?? 0;

  @override
  int? get totalBytes => _as<MultipleTransferOperationStatus>()?.bytesTotal;

  @override
  double? get bytesPerSecond => _as<MeasurableOperationStatus>()?.speed;

  @override
  Duration? get remaining => _as<MeasurableOperationStatus>()?.remaining;

  @override
  String get itemName => _as<SingleTransferOperationStatus>()?.itemName ?? '';

  @override
  int get itemBytes => _as<SingleTransferOperationStatus>()?.itemBytesTransferred ?? 0;

  @override
  int? get itemTotalBytes => _as<SingleTransferOperationStatus>()?.itemBytesTotal;

  /// Ход по текущему объекту: без него большой файл выглядит как остановка —
  /// общий счёт по нему не двигается до самого конца.
  @override
  double? get itemProgress {
    final size = itemTotalBytes;
    if (size == null || size <= 0) {
      return null;
    }
    return (itemBytes / size).clamp(0.0, 1.0);
  }

  @override
  String? get stageLabel {
    final stages = _as<MultistageOperationStatus>()?.stages ?? const <StageOperationStatus>[];
    final current = stages.indexWhere((stage) => stage.name.isNotEmpty);
    if (current < 0) {
      return null;
    }
    return '${current + 1} of ${stages.length} — ${stages[current].name}';
  }

  @override
  bool get isRunning => _operation?.state.isFinished == false;

  /// Прогон начался и ещё не закрыт окном: операция идёт или доигрывает.
  bool get isBusy => _operation != null;

  /// Завершение прогона: успешное, с ошибкой или отменённое.
  @override
  Future<void> get completion => _completion.future;
}
