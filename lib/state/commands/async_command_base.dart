import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../model/async/async_operation.dart';
import '../../model/async/operation_request.dart';
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
  double? _progressValue;
  String _message = '';

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
    _progressValue = null;
    _message = message;
    _operation = operation;
    notifyListeners();

    // Подписки ставятся сразу: операция начинает работу следующим шагом цикла
    // событий и до тех пор ничего не теряется.
    _progress = operation.progress.listen((event) {
      _progressValue = event.percent;
      _message = event.message;
      notifyListeners();
    });
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
      _running = false;
      _question = null;
      notifyListeners();
    }
  }

  /// Ответ на вопрос, заданный по ходу работы.
  void answer(OperationOption option) {
    _question?.respond(option);
    _question = null;
    notifyListeners();
  }

  // --- AsyncCommand ---

  @override
  double? get progress => _progressValue;

  @override
  String get progressMessage => _message;

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
