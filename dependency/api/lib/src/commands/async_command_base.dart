import 'dart:async';

import 'package:flutter/foundation.dart';

import '../async/async_operation.dart';
import '../async/operation_request.dart';
import '../async/operation_status.dart';
import '../util/throttle.dart';
import '../background/operations.dart';
import 'app_command.dart';

/// Команда, работа которой занимает время: удаление, копирование, перенос.
///
/// Здесь собрано всё, что у таких команд одинаково: подписки на ход работы и
/// на вопросы операции, признак занятости, отмена и завершение. Команде
/// остаётся описать саму работу — [runOperation] и всё, что до и после.
///
/// Вопрос операции («файл уже есть, что делать?») показывается в окне команды,
/// а если окна нет — берётся ответ по умолчанию: команду мог запустить
/// сценарий, и спросить там некого.
abstract class AsyncCommandBase extends AppCommand implements AsyncCommand {
  AsyncOperation<void>? _operation;
  StreamSubscription<OperationRequest>? _requests;
  OperationStatus? _watched;

  OperationProgress _state = const OperationProgress();

  /// Вопрос, на который сейчас ждут ответа.
  OperationRequest? _question;

  final Completer<void> _completion = Completer<void>();

  @override
  bool get hasDialog => true;

  /// Длительную работу можно оставить идти без окна: ход дела она рассказывает
  /// сама ([TaskStatus]), а окна ей нужно ровно столько, сколько нужно
  /// пользователю.
  @override
  bool get canRunInBackground => true;

  /// Заголовок для общего места фоновых работ.
  @override
  String get title => dialogTitle;

  /// Есть ли что прерывать прямо сейчас.
  @override
  bool get canCancel => isRunning;

  @override
  String get message => progressMessage;

  /// Вопрос, который показывает окно команды; null — вопроса нет.
  OperationRequest? get question => _question;

  /// Заголовок разбора, когда работа не удалась: окно показывает его вместо
  /// хода дела.
  ///
  /// Форму назад оно не пускает — правки ввода тут уже ничего не изменят,
  /// работа была начата, — поэтому сказать, что именно не вышло, больше некому.
  String get failureMessage => '$label failed';

  /// Выполняет операцию, показывая её ход. Отмена пользователем ошибкой
  /// не считается: сделанное остаётся сделанным.
  @protected
  Future<void> runOperation(AsyncOperation<void> operation, {required String message}) async {
    // По [isBusy], а не по [isRunning]: прогон, который уже кончился, повторять
    // тоже нечего — экземпляр команды живёт один запуск.
    if (isBusy) {
      return;
    }

    _state = OperationProgress(message: message);
    _operation = operation;
    // Работа заведена: с этого момента её можно найти. В статусной области её
    // пока нет — туда она попадёт, только если её отправят в фон.
    contextOrNull?.app.operations.register(
      OperationRun(runId: runId, operation: operation, commandId: id, title: title),
    );
    notifyListeners();

    // Подписки ставятся сразу: операция начинает работу следующим шагом цикла
    // событий и до тех пор ничего не теряется.
    // Подписка, а не поток: ход работы — объект, и читается он весь сразу.
    _watched = operation.status;
    _watched!.addListener(_onStatusChanged);
    _requests = operation.requests.listen((request) {
      if (!hasOpenDialog && !isInBackground) {
        // Спросить некого: команду запустил сценарий или список команд.
        request.respond(request.enterOption);
        return;
      }
      if (isInBackground) {
        // Окно само не выпрыгивает: вырывать человека из другого дела нельзя,
        // а вопрос никуда не денется — работа ждёт столько, сколько нужно.
        // Но и молчать нельзя, иначе она стоит, а он этого не замечает: у
        // полоски в статусной области загорается кнопка, и об этом говорится
        // тостом — один раз, в тот момент, когда работа упёрлась.
        contextOrNull?.app.toasts.show('$title: waiting for an answer');
      }
      _question = request;
      notifyListeners();
    });

    try {
      await operation.result;
    } on OperationCanceled {
      // Прервано пользователем.
    } finally {
      _watched?.removeListener(_onStatusChanged);
      _watched = null;
      contextOrNull?.app.operations.forget(runId);
      unawaited(_requests?.cancel());
      _redraw.cancel();
      // Работа остаётся на месте: прогон не кончен, пока не закрыто окно.
      // Иначе оно на весь хвост — отпустить аренду, перечитать панели —
      // откатилось бы к форме с параметрами.
      _question = null;
      // Прогон закончился — успехом, ошибкой или отменой. Раньше [completion]
      // завершалось только в [submit], и ждущий отменённой или запущенной без
      // окна работы не дожидался её никогда.
      _finishRun();
      notifyListeners();
    }
  }

  /// Окно перерисовывается не на каждое сообщение операции: копирование мелких
  /// файлов идёт куда быстрее, чем имеет смысл обновлять экран.
  late final Throttle _redraw = Throttle(notifyListeners);

  /// Собирает снимок хода из того, что рассказал статус.
  ///
  /// Переходное: наружу команда отдаёт поля по одному, и снимок избавляет от
  /// того, чтобы переписывать их все разом. Уйдёт вместе с [AsyncCommandBase].
  static OperationProgress _snapshot(OperationStatus status) {
    final stages = status is MultistageOperationStatus ? status.stages : const <StageOperationStatus>[];
    final current = stages.indexWhere((stage) => stage.name.isNotEmpty);
    return OperationProgress(
      percent: status is ComputableOperationStatus ? status.percentProgress : null,
      message: status.message,
      processed: status is MultipleTransferOperationStatus ? status.itemsTransferred : 0,
      total: status is MultipleTransferOperationStatus ? status.itemsTotal : null,
      totalIsFinal: status is MultipleTransferOperationStatus ? status.totalIsFinal : true,
      bytes: status is MultipleTransferOperationStatus ? status.bytesTransferred : 0,
      totalBytes: status is MultipleTransferOperationStatus ? status.bytesTotal : null,
      bytesPerSecond: status is MeasurableOperationStatus ? status.speed : null,
      itemName: status is SingleTransferOperationStatus ? status.itemName : '',
      itemBytes: status is SingleTransferOperationStatus ? status.itemBytesTransferred : 0,
      itemTotalBytes: status is SingleTransferOperationStatus ? status.itemBytesTotal : null,
      stage: current < 0 ? 0 : current + 1,
      stageCount: stages.length,
      stageName: current < 0 ? '' : stages[current].name,
    );
  }

  void _onStatusChanged() {
    final status = _watched;
    if (status == null) {
      return;
    }
    _onProgress(_snapshot(status));
  }

  void _onProgress(OperationProgress event) {
    _state = event;
    _redraw();
  }

  /// Что набрано в поле вопроса — если у вопроса есть поле.
  ///
  /// Хранится здесь, а не в окне: отвечает на вопрос и кнопка, и Enter, который
  /// перехватывает ядро, — и оба должны видеть одно и то же. То же правило, что
  /// и у окон с параметрами: значение задаётся по мере ввода.
  String _answerText = '';

  void setAnswerText(String value) => _answerText = value;

  /// Ответ на вопрос, заданный по ходу работы.
  void answer(OperationRequestOption option) {
    _question?.respond(option, text: _answerText);
    _question = null;
    _answerText = '';
    notifyListeners();
  }

  // --- AsyncCommand ---

  @override
  double? get progress => _state.percent;

  @override
  String get progressMessage => _state.message;

  @override
  int get processed => _state.processed;

  @override
  int? get total => _state.total;

  @override
  bool get totalIsFinal => _state.totalIsFinal;

  @override
  int get bytes => _state.bytes;

  @override
  int? get totalBytes => _state.totalBytes;

  @override
  double? get bytesPerSecond => _state.bytesPerSecond;

  @override
  Duration? get remaining => _state.remaining;

  @override
  String get itemName => _state.itemName;

  @override
  int get itemBytes => _state.itemBytes;

  @override
  int? get itemTotalBytes => _state.itemTotalBytes;

  /// Ход по текущему объекту: без него большой файл выглядит как остановка —
  /// общий счёт по нему не двигается до самого конца.
  @override
  double? get itemProgress => _state.itemPercent;

  @override
  String? get stageLabel => _state.hasStages ? '${_state.stage} of ${_state.stageCount} — ${_state.stageName}' : null;

  @override
  bool get isRunning => _operation?.state.isFinished == false;

  /// Прогон начался и ещё не закрыт окном: операция идёт или команда доигрывает.
  ///
  /// Отдельной фазы для этого не нужно: работа заведена — значит прогон начат,
  /// и возвращаться к форме не к чему. Это и есть охрана от того, что `Enter`,
  /// нажатый в момент завершения — а он нажимается именно тогда, потому что на
  /// экране форма с кнопкой, — запускал работу второй раз.
  bool get isBusy => _operation != null;

  /// Завершение прогона: успешное, с ошибкой или отменённое.
  ///
  /// Именно прогона, а не команды: если работа упала и окно осталось открытым,
  /// повторная попытка — это уже другой прогон, а ждущий первого дождался его
  /// исхода.
  @override
  Future<void> get completion => _completion.future;

  /// Отмечает прогон законченным. Повторные вызовы ничего не делают.
  void _finishRun() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  /// Убрать окно, оставив работу идти.
  ///
  /// Решение принимает ядро — команда только просит: у неё нет ни списка
  /// фоновых работ, ни места, где его показывают.
  void sendToBackground() => context.app.operations.sendToBackground(runId, owner: context.app.view.sourceArea);

  /// Прервать работу — по кнопке в окне или по Esc.
  ///
  /// Не молча: операция задаст вопрос и **встанет** до ответа. Работа файлового
  /// менеджера необратима, а Esc нажимают не глядя, поэтому цена случайного
  /// нажатия — прерванное копирование посреди дерева.
  @override
  void cancel() {
    if (!isRunning) {
      // Работа ещё не началась — отмена означает «закрыть окно».
      closeDialog();
      return;
    }
    _operation?.requestCancel();
  }

  /// Enter: пока идёт вопрос — вариант по умолчанию, иначе как у всех.
  ///
  /// «Вариант по умолчанию» и «что делает Enter» — это одно и то же, поэтому
  /// отдельного поля вопросу не нужно.
  @override
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

    await super.submit();
    if (error == null) {
      // Ошибка оставляет окно открытым: ввод можно исправить и повторить,
      // и тогда прогон ещё не закончен.
      _finishRun();
    }
  }

  /// Esc: пока идёт вопрос — его вариант для Esc; во время работы — просьба
  /// прервать; в остальное время — закрыть окно.
  @override
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
      // Работа кончилась и окно закроется само, как только команда доиграет.
      // Закрывать его по Esc раньше нечестно: пропала бы ошибка, если хвост
      // ещё успеет её принести.
      return;
    }
    super.dismiss();
    // Окно закрыли, так и не начав работу: ждать больше нечего.
    _finishRun();
  }
}
