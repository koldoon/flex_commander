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
    this.bytes = 0,
    this.totalBytes,
    this.bytesPerSecond,
    this.itemName = '',
    this.itemBytes = 0,
    this.itemTotalBytes,
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

  /// Сколько байт уже перенесено.
  ///
  /// Объекты плохо описывают работу: копирование одного файла на четыре
  /// гигабайта — это «0 из 1» до самого конца. Байты растут ровно, и по ним же
  /// считается скорость.
  final int bytes;

  /// Сколько байт всего; null — размер не известен и известен не будет
  /// (удаление в корзину, источник без размеров). Досчитан ли он — говорит
  /// тот же [totalIsFinal].
  final int? totalBytes;

  /// Скорость, байт в секунду; null — считать пока не из чего.
  ///
  /// Считает её тот, кто ведёт работу (движок переноса), а не провайдер:
  /// провайдер не знает ни про очередь заданий, ни про то, сколько их ещё.
  final double? bytesPerSecond;

  /// Объект, который обрабатывается прямо сейчас; пустая строка — работа не
  /// разбита на объекты (или он ещё не начат).
  final String itemName;

  /// Сколько байт этого объекта уже прошло.
  ///
  /// Отдельно от [bytes] потому, что одно другого не заменяет: общий счёт
  /// говорит, сколько осталось работы, а этот — сколько осталось у файла, на
  /// котором всё встало. Файл на четыре гигабайта в общем счёте выглядит одним
  /// объектом из тысячи, и по нему не видно ничего.
  final int itemBytes;

  /// Сколько байт в текущем объекте; null — размер неизвестен.
  final int? itemTotalBytes;

  /// Доля текущего объекта, 0.0…1.0; null — показывать нечего.
  double? get itemPercent {
    final size = itemTotalBytes;
    if (size == null || size <= 0) {
      return null;
    }
    return (itemBytes / size).clamp(0.0, 1.0);
  }

  /// 0.0…1.0 или null, если прогресс неопределённый.
  double? get percent {
    if (_percent != null) {
      return _percent;
    }

    // Байты честнее объектов везде, где они известны.
    final bytesTotal = totalBytes;
    if (bytesTotal != null && bytesTotal > 0) {
      return (bytes / bytesTotal).clamp(0.0, 1.0);
    }

    final count = total;
    if (count == null || count <= 0) {
      return null;
    }
    // Пока идёт подсчёт, обработанных может оказаться больше, чем насчитано:
    // доля всё равно не должна выходить за единицу.
    return (processed / count).clamp(0.0, 1.0);
  }

  /// Сколько ещё ждать; null — считать не из чего.
  ///
  /// Пока подсчёт не закончен ([totalIsFinal]), это оценка по нижней границе:
  /// работы окажется больше, а не меньше.
  Duration? get remaining {
    final speed = bytesPerSecond;
    final bytesTotal = totalBytes;
    if (speed == null || speed <= 0 || bytesTotal == null || bytesTotal <= bytes) {
      return null;
    }
    return Duration(seconds: ((bytesTotal - bytes) / speed).round());
  }

  @override
  String toString() => 'OperationProgress($percent, $message, $processed/$total, $bytes/$totalBytes)';
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

  /// Прервать немедленно, ни о чём не спрашивая.
  void cancel();

  /// Попросить прервать: работа встанет на ближайшей проверке и спросит
  /// подтверждение — обычным [OperationRequest], как и всё остальное.
  ///
  /// Отдельно от [cancel], потому что это разные действия: закрытие окна или
  /// уход из приложения прерывают молча, а нажатие Esc — с вопросом. Пока
  /// пользователь думает, работа не идёт: тело операции ждёт ответа.
  void requestCancel();
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

  /// Пользователь просил прервать, но ещё не подтвердил.
  bool _cancelRequested = false;

  /// Бросает [OperationCanceled], если операцию успели отменить.
  /// Вызывается телом операции между шагами.
  void checkCanceled() {
    if (isCanceled) {
      throw const OperationCanceled();
    }
  }

  @override
  void requestCancel() {
    if (_status.isFinished) {
      return;
    }
    _cancelRequested = true;
  }

  /// Проверка между шагами работы: отмена и просьба прервать.
  ///
  /// Заменяет [checkCanceled] везде, где можно подождать. Просьба прервать
  /// превращается здесь в обычный вопрос, и пауза выходит сама собой: тело
  /// операции стоит на `await`, пока пользователь не ответит. Отдельного
  /// «поставить на паузу» поэтому не нужно.
  ///
  /// Спросить некого (окна нет, работу запустил сценарий) — берётся вариант по
  /// умолчанию, то есть «прервать»: это ровно то, о чём просили.
  Future<void> checkpoint() async {
    checkCanceled();
    if (!_cancelRequested) {
      return;
    }

    // Сбрасывается до вопроса, а не после: пока ждём ответа, пользователь
    // может нажать Esc ещё раз, и это должно значить новый вопрос, а не
    // повтор старого сразу после «продолжить».
    _cancelRequested = false;

    final answer = await ask(
      OperationRequest(
        message: 'Abort the operation?',
        options: const [OperationOption.abort, OperationOption.resume],
        defaultOption: OperationOption.abort,
        escapeOption: OperationOption.resume,
      ),
    );

    if (answer == OperationOption.abort) {
      cancel();
    }
    checkCanceled();
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

  /// Прерывать нечего: работа кончилась раньше, чем её попросили прервать.
  @override
  void requestCancel() {}
}
