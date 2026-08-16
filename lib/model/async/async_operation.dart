import 'dart:async';

import 'operation_request.dart';

/// Состояние операции.
///
/// [pending] пока не используется: он появится, когда операции начнут
/// выстраиваться в очередь (копирование нескольких пакетов файлов).
enum OperationStatus {
  inited,
  pending,
  processing,
  complete,
  canceled,
  error;

  bool get isFinished => this == complete || this == canceled || this == error;
}

/// Прогресс операции.
///
/// Доля выполненного считается из двух счётчиков: сколько объектов уже
/// обработано и сколько их всего. Второе число может быть неизвестно или
/// известно лишь частично — обход большого дерева сам по себе долгий, и
/// операции считают его фоном, не задерживая начало работы.
class OperationProgress {
  const OperationProgress({
    double? percent,
    this.message = '',
    this.processed = 0,
    this.total,
    this.totalIsFinal = true,
  }) : _percent = percent;

  final double? _percent;

  final String message;

  /// Сколько объектов обработано.
  final int processed;

  /// Сколько объектов всего; null — пока неизвестно.
  final int? total;

  /// Досчитан ли [total] до конца. Пока нет, это нижняя оценка, и показывать
  /// её как окончательную нельзя.
  final bool totalIsFinal;

  /// 0.0…1.0 или null, если прогресс неопределённый.
  double? get percent {
    if (_percent != null) {
      return _percent;
    }
    final count = total;
    if (count == null || count <= 0) {
      return null;
    }
    // Пока идёт подсчёт, обработанных может оказаться больше, чем насчитано:
    // доля всё равно не должна выходить за единицу.
    return (processed / count).clamp(0.0, 1.0);
  }

  @override
  String toString() => 'OperationProgress($percent, $message, $processed/$total)';
}

/// Операция отменена вызовом [AsyncOperation.cancel].
class OperationCanceled implements Exception {
  const OperationCanceled();

  @override
  String toString() => 'OperationCanceled';
}

/// Асинхронная операция: результат, прогресс, отмена и вопросы пользователю.
///
/// От голого [Future] отличается тремя вещами, без которых не обойтись
/// файловому менеджеру: операцию можно отменить, она умеет сообщать о ходе
/// работы и задавать вопросы (перезаписать? пропустить?) не прерываясь.
abstract class AsyncOperation<T> {
  OperationStatus get status;

  /// Результат. Завершается ошибкой [FsError] или [OperationCanceled].
  Future<T> get result;

  /// Прогресс. Быстрые операции могут не отдавать ничего.
  Stream<OperationProgress> get progress;

  /// Вопросы пользователю. Пустой поток у операций, которые ничего не спрашивают.
  Stream<OperationRequest> get requests;

  void cancel();
}

/// Базовая реализация [AsyncOperation] для операций, выполняемых в текущем
/// изоляте. Тело операции получает саму операцию, чтобы сообщать прогресс,
/// задавать вопросы и проверять отмену.
class TaskOperation<T> implements AsyncOperation<T> {
  /// Создаёт и запускает операцию.
  ///
  /// Тело стартует не мгновенно, а следующим шагом цикла событий: вызывающий
  /// код должен успеть подписаться на прогресс и на вопросы, а он делает это
  /// строкой ниже. Иначе первые события — и первый вопрос — прошли бы мимо.
  TaskOperation(this._body) {
    scheduleMicrotask(_run);
  }

  final Future<T> Function(TaskOperation<T> op) _body;

  final Completer<T> _completer = Completer<T>();
  final StreamController<OperationProgress> _progress = StreamController<OperationProgress>.broadcast();
  final StreamController<OperationRequest> _requests = StreamController<OperationRequest>.broadcast();

  OperationStatus _status = OperationStatus.inited;

  @override
  OperationStatus get status => _status;

  @override
  Future<T> get result => _completer.future;

  OperationProgress? _lastProgress;

  /// Прогресс операции.
  ///
  /// Новый подписчик первым делом получает последнее известное состояние:
  /// операция стартует сразу при создании, и тот, кто подписался следующей
  /// строкой, иначе пропустил бы уже случившееся.
  @override
  Stream<OperationProgress> get progress async* {
    final last = _lastProgress;
    if (last != null) {
      yield last;
    }
    yield* _progress.stream;
  }

  @override
  Stream<OperationRequest> get requests => _requests.stream;

  bool get isCanceled => _status == OperationStatus.canceled;

  /// Бросает [OperationCanceled], если операцию успели отменить.
  /// Вызывается телом операции между шагами.
  void checkCanceled() {
    if (isCanceled) {
      throw const OperationCanceled();
    }
  }

  void report(OperationProgress value) {
    _lastProgress = value;
    if (!_progress.isClosed) {
      _progress.add(value);
    }
  }

  /// Задаёт вопрос пользователю и ждёт ответа.
  /// Если вопрос никто не слушает, возвращается вариант по умолчанию.
  Future<OperationOption> ask(OperationRequest request) {
    if (_requests.hasListener) {
      _requests.add(request);
      return request.answer;
    }
    return Future.value(request.defaultOption);
  }

  @override
  void cancel() {
    if (_status.isFinished) {
      return;
    }
    _status = OperationStatus.canceled;
    _finish();
    if (!_completer.isCompleted) {
      _completer.completeError(const OperationCanceled());
    }
  }

  Future<void> _run() async {
    if (isCanceled) {
      // Отменили ещё до старта.
      return;
    }
    _status = OperationStatus.processing;
    try {
      final value = await _body(this);
      if (isCanceled) {
        return;
      }
      _status = OperationStatus.complete;
      _finish();
      _completer.complete(value);
    } catch (error, stackTrace) {
      if (isCanceled) {
        return;
      }
      _status = error is OperationCanceled ? OperationStatus.canceled : OperationStatus.error;
      _finish();
      if (!_completer.isCompleted) {
        _completer.completeError(error, stackTrace);
      }
    }
  }

  void _finish() {
    _progress.close();
    _requests.close();
  }
}

/// Уже завершённая операция. Удобна для заглушек и тестов.
class CompletedOperation<T> implements AsyncOperation<T> {
  CompletedOperation(T value) : result = Future.value(value);

  CompletedOperation.error(Object error) : result = Future.error(error), _status = OperationStatus.error {
    // Ошибка обязательно должна быть кем-то прочитана, иначе Dart сообщит
    // о необработанной ошибке ещё до того, как её заберёт вызывающий код.
    result.ignore();
  }

  @override
  final Future<T> result;

  OperationStatus _status = OperationStatus.complete;

  @override
  OperationStatus get status => _status;

  @override
  Stream<OperationProgress> get progress => const Stream.empty();

  @override
  Stream<OperationRequest> get requests => const Stream.empty();

  @override
  void cancel() {}
}
