import 'dart:async';

import 'package:flutter/foundation.dart';

import '../async/async_operation.dart';
import '../async/operation_request.dart';
import '../util/throttle.dart';
import '../background/task_status.dart';
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
abstract class AsyncCommandBase extends AppCommand implements AsyncCommand, TaskStatus {
  AsyncOperation<void>? _operation;
  StreamSubscription<OperationRequest>? _requests;
  StreamSubscription<OperationProgress>? _progress;

  bool _running = false;
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

  @override
  TaskStatus? get status => this;

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

  /// Выполняет операцию, показывая её ход. Отмена пользователем ошибкой
  /// не считается: сделанное остаётся сделанным.
  @protected
  Future<void> runOperation(AsyncOperation<void> operation, {required String message}) async {
    if (_running) {
      return;
    }

    _running = true;
    _state = OperationProgress(message: message);
    _operation = operation;
    notifyListeners();

    // Подписки ставятся сразу: операция начинает работу следующим шагом цикла
    // событий и до тех пор ничего не теряется.
    _progress = operation.progress.listen(_onProgress);
    _requests = operation.requests.listen((request) {
      if (!hasOpenDialog && !isInBackground) {
        // Спросить некого: команду запустил сценарий или список команд.
        request.respond(request.defaultOption);
        return;
      }
      if (isInBackground) {
        // Работа шла без окна, но появился вопрос — отвечать за пользователя
        // ядро не вправе, поэтому окно возвращается на вид.
        context.app.background.bringToFront(runId);
      }
      _question = request;
      notifyListeners();
    });

    try {
      await operation.result;
    } on OperationCanceled {
      // Прервано пользователем.
    } finally {
      unawaited(_progress?.cancel());
      unawaited(_requests?.cancel());
      _redraw.cancel();
      _running = false;
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
  void answer(OperationOption option) {
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
  bool get isRunning => _running;

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
  void sendToBackground() => context.app.background.sendToBackground(runId);

  /// Прервать работу — по кнопке в окне или по Esc.
  ///
  /// Не молча: операция задаст вопрос и **встанет** до ответа. Работа файлового
  /// менеджера необратима, а Esc нажимают не глядя, поэтому цена случайного
  /// нажатия — прерванное копирование посреди дерева.
  @override
  void cancel() {
    if (!_running) {
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
      answer(question.defaultOption);
      return;
    }
    if (isRunning) {
      // Работа идёт: подтверждать нечего, она уже запущена.
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
    super.dismiss();
    // Окно закрыли, так и не начав работу: ждать больше нечего.
    _finishRun();
  }
}
