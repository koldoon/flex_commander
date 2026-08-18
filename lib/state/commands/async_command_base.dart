import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../model/async/async_operation.dart';
import '../../model/async/operation_request.dart';
import '../throttle.dart';
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
  StreamSubscription<OperationProgress>? _progress;

  bool _running = false;
  OperationProgress _state = const OperationProgress();

  /// Вопрос, на который сейчас ждут ответа.
  OperationRequest? _question;

  final Completer<void> _completion = Completer<void>();

  @override
  bool get hasDialog => true;

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
      if (!hasOpenDialog) {
        request.respond(request.defaultOption);
        return;
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

  /// Ответ на вопрос, заданный по ходу работы.
  void answer(OperationOption option) {
    _question?.respond(option);
    _question = null;
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
  bool get isRunning => _running;

  @override
  Future<void> get completion => _completion.future;

  @override
  void cancel() {
    _operation?.cancel();
    if (!_running) {
      // Работа ещё не началась — отмена означает «закрыть окно».
      closeDialog();
    }
  }

  @override
  Future<void> submit() async {
    await super.submit();
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }
}
