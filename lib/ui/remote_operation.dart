import 'dart:async';

import 'package:fc_api/fc_api.dart';

import '../link/link.dart';

/// Работа, идущая за границей, — здесь она обычная [Operation].
///
/// Ход дела в `status`, вопросы в `requests`, `cancel()` — сообщение. Ни окно
/// копирования, ни статусная область, ни `FcAsyncRun` не знают, что работа
/// идёт не тут: они написаны против [Operation], и переучивать их было бы
/// ошибкой — окно работы одно на приложение (`docs/spec/client-server.md`, §7).
class RemoteOperation implements Operation<OperationSpec, void> {
  RemoteOperation(this._link) {
    _events = _link.events.listen(_apply);
  }

  final Link _link;
  late final StreamSubscription<CoreEvent> _events;

  static var _nextRun = 0;

  /// Имя даёт **эта** сторона, до запуска: подписка встаёт раньше, и первое же
  /// событие не проходит мимо.
  late final String runId = 'run#${_nextRun++}';

  @override
  late final MutableOperationStatus status = MutableOperationStatus();

  final Completer<void> _completer = Completer<void>();
  final StreamController<OperationRequest> _requests = StreamController<OperationRequest>.broadcast();

  OperationRequest? _asked;
  OperationState _state = OperationState.inited;

  @override
  OperationState get state => _state;

  @override
  Future<void> get result => _completer.future;

  @override
  Stream<OperationRequest> get requests => _requests.stream;

  @override
  void start(OperationSpec params) {
    if (_state != OperationState.inited) {
      return;
    }
    // Состояние ставится молча: о том, что работа началась, скажет она сама
    // первым же отчётом. Уведомить здесь значило бы сказать «дело пошло»
    // раньше, чем оно пошло, — а окно по этому и отличает отказ от неудачи.
    _state = OperationState.processing;
    _link.tell(RunOperation(runId, params));
  }

  @override
  void cancel() => _link.tell(TellOperation(runId, const CancelInput()));

  @override
  void requestCancel() => _link.tell(TellOperation(runId, const SoftCancelInput()));

  Future<void> run(OperationSpec params) {
    start(params);
    return result;
  }

  void _apply(CoreEvent event) {
    switch (event) {
      case OperationProgress(runId: final id, :final report) when id == runId:
        _state = report.state;
        status.apply(report);
        status.setState(report.state);

      case OperationAsked(runId: final id, :final ask) when id == runId:
        _ask(ask);

      case OperationAskCanceled(runId: final id) when id == runId:
        // Вопрос снят вместе с работой: окно закрывается, а не ждёт ответа,
        // которого уже никто не примет.
        _asked = null;
        status.setRequest(null);

      case OperationEnded(runId: final id, :final outcome, :final error, :final message) when id == runId:
        _end(outcome, error, message);

      case CoreEvent():
        break;
    }
  }

  void _ask(AskSpec ask) {
    if (!_requests.hasListener) {
      // Спросить некого: работу запустили без окна — сценарием, клавишей с
      // готовым согласием. Берётся вариант по умолчанию, то есть тот же, что
      // сработал бы по `Enter`. Молчать нельзя: работа встанет и будет ждать
      // ответа, которого никто не даст.
      _link.tell(TellOperation(runId, AnswerInput(ask.enterOptionId)));
      return;
    }

    final options = [for (final entry in ask.options.entries) OperationRequestOption(entry.key, entry.value)];
    OperationRequestOption optionOf(String? id) =>
        options.firstWhere((option) => option.id == id, orElse: () => options.first);

    final request = OperationRequest(
      message: ask.message,
      options: options,
      enterOption: optionOf(ask.enterOptionId),
      escapeOption: ask.escapeOptionId == null ? null : optionOf(ask.escapeOptionId),
      inputLabel: ask.inputLabel,
      secret: ask.secret,
    );
    _asked = request;
    status.setRequest(request);
    _requests.add(request);

    // Ответ уходит той стороне: здесь у вопроса только вид, а ждёт его работа
    // за границей.
    unawaited(
      request.answer.then((option) {
        if (!identical(_asked, request)) {
          return;
        }
        _asked = null;
        status.setRequest(null);
        _link.tell(TellOperation(runId, AnswerInput(option.id, text: request.text)));
      }),
    );
  }

  void _end(OperationOutcome outcome, FsError? error, String message) {
    if (_completer.isCompleted) {
      return;
    }
    _asked = null;
    status.setRequest(null);
    switch (outcome) {
      case OperationOutcome.done:
        _setState(OperationState.complete);
        _completer.complete();
      case OperationOutcome.canceled:
        _setState(OperationState.canceled);
        _completer.completeError(const OperationCanceled());
      case OperationOutcome.failed:
        _setState(OperationState.error);
        _completer.completeError(error ?? Exception(message));
    }
    unawaited(_events.cancel());
    unawaited(_requests.close());
  }

  void _setState(OperationState value) {
    _state = value;
    status.setState(value);
  }
}
