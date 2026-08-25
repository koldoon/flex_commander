import 'dart:async';

import 'package:flutter/foundation.dart';

import 'operation_request.dart';
import 'operation_status.dart';

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
    this.stage = 0,
    this.stageCount = 0,
    this.stageName = '',
    this.indeterminate = false,
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

  /// Который сейчас идёт этап работы, считая с единицы; 0 — этапов нет.
  ///
  /// Этап — это плечо работы, у которого своя мера: «упаковать», а потом
  /// «отдать приёмнику»; «скопировать записи», а потом «пересобрать архив».
  /// Плечи заводятся только там, где второе действительно долгое, — у обычного
  /// копирования файла этапов нет вовсе, и окно о них не заикается.
  final int stage;

  /// Сколько всего этапов; 0 или 1 — работа одноплечая.
  final int stageCount;

  /// Чем занят текущий этап: «repacking archive», «uploading».
  final String stageName;

  /// Сколько осталось — неизвестно, и врать долей нельзя.
  ///
  /// Так идёт пересборка архива: сколько в ней работы, до конца не знает никто,
  /// а полоса, замершая на ста процентах, выглядит как зависшая программа.
  final bool indeterminate;

  /// Есть ли о чём говорить: этапы показываются, только когда их больше одного.
  bool get hasStages => stageCount > 1 && stage > 0;

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
    if (indeterminate) {
      return null;
    }
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
  OperationState get state;

  /// Ход работы: объект, а не поток. Читается всегда, подписка не обязательна.
  OperationStatus get status;

  /// Результат. Завершается ошибкой [FsError] или [OperationCanceled].
  Future<T> get result;

  /// Прогресс потоком.
  ///
  /// Переходное: ход работы держит [status], а поток из него питается —
  /// источник правды один. Уйдёт, когда потребители перейдут на объект.
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
  final StreamController<OperationRequest> _requests = StreamController<OperationRequest>.broadcast();

  OperationState _state = OperationState.inited;

  @override
  OperationState get state => _state;

  @override
  late final OperationStatus status = _status;

  final _TaskOperationStatus _status = _TaskOperationStatus();

  @override
  Future<T> get result => _completer.future;

  final StreamController<OperationProgress> _progress = StreamController<OperationProgress>.broadcast();

  /// Новый подписчик первым делом получает последнее известное: операция
  /// стартует сразу при создании, и подписавшийся следующей строкой иначе
  /// пропустил бы уже случившееся.
  @override
  Stream<OperationProgress> get progress async* {
    final last = _status.lastProgress;
    if (last != null) {
      yield last;
    }
    yield* _progress.stream;
  }

  /// Переводит состояние и сообщает об этом наружу одним движением.
  void _setState(OperationState value) {
    _state = value;
    _status.setState(value);
  }

  @override
  Stream<OperationRequest> get requests => _requests.stream;

  bool get isCanceled => _state == OperationState.canceled;

  /// Пользователь просил прервать, но ещё не подтвердил.
  bool _cancelRequested = false;

  /// Вложенные операции, которые идут прямо сейчас.
  ///
  /// Список, а не одна ссылка: тело зовёт [delegate] из разных мест — разбор
  /// пути рекурсивен, — и вложенных по дороге может оказаться несколько.
  /// Прерывают всегда снаружи, а работает самая вложенная, и добраться до неё
  /// можно только по такому списку.
  final List<AsyncOperation<Object?>> _delegated = [];

  /// Бросает [OperationCanceled], если операцию успели отменить.
  /// Вызывается телом операции между шагами.
  void checkCanceled() {
    if (isCanceled) {
      throw const OperationCanceled();
    }
  }

  @override
  void requestCancel() {
    if (_state.isFinished) {
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
        options: const [OperationRequestOption.abort, OperationRequestOption.resume],
        enterOption: OperationRequestOption.abort,
        escapeOption: OperationRequestOption.resume,
      ),
    );

    if (answer == OperationRequestOption.abort) {
      cancel();
    }
    checkCanceled();
  }

  /// Вопрос об отмене задан, а ответа ещё нет.
  ///
  /// Нужен только [keepRunning]: он зовётся на каждом куске работы, и без
  /// защёлки окно спрашивало бы одно и то же по десять раз в секунду.
  bool _asking = false;

  /// Отмена для работы, которую нельзя ни приостановить, ни возобновить.
  ///
  /// Возвращает false, когда работу пора бросить. Просьбу прервать превращает в
  /// тот же вопрос, что и [checkpoint], но ответа **не ждёт**: остановить
  /// системное копирование файла на середине нельзя, а стоять на месте, пока
  /// файл всё равно копируется, — обман. Пока пользователь думает, работа идёт
  /// и полоса движется; ответ «прервать» доходит до неё следующим куском.
  ///
  /// Зовётся оттуда, где ждать нечем: из синхронного колбэка чужого кода.
  /// Поэтому и вопрос уходит в свой такт, а об отмене зовущий узнаёт из
  /// следующего false, а не из броска посреди чужой работы.
  bool keepRunning() {
    if (isCanceled) {
      return false;
    }
    if (_cancelRequested && !_asking) {
      _asking = true;
      // Тот же checkpoint: второго места, где задаётся этот вопрос, заводить
      // незачем. Его бросок здесь глотается — отмену зовущий увидит сам.
      unawaited(checkpoint().catchError((Object _) {}).whenComplete(() => _asking = false));
    }
    return true;
  }

  /// Пересказывает ход чужой работы как свой, не забирая над ней власти.
  ///
  /// Отмена вниз при этом **не** идёт — тем и отличается от [delegate]: за
  /// смонтированным источником стоит очередь арендаторов, и один ушедший не
  /// вправе прервать то, чего ждут остальные.
  ///
  /// Возвращает то, чем пересказ прекратить.
  VoidCallback relayFrom(AsyncOperation<Object?> source) {
    final status = source.status;
    if (status is! _TaskOperationStatus) {
      return () {};
    }

    OperationProgress? relayed;
    void relay() {
      final last = status.lastProgress;
      // Только новое: ход и смена состояния сообщают об одном и том же
      // объекте, и пересказывать его дважды значило бы удвоить каждый шаг.
      if (last == null || identical(last, relayed)) {
        return;
      }
      relayed = last;
      report(last);
    }

    status.addListener(relay);
    relay();
    return () => status.removeListener(relay);
  }

  void report(OperationProgress value) {
    if (_state.isFinished) {
      // Отчёт вложенной операции, доехавший после конца работы: рассказывать
      // про шаг, которого уже не было, незачем.
      return;
    }
    _status.update(value);
    if (!_progress.isClosed) {
      _progress.add(value);
    }
  }

  /// Веха: чем работа занята сейчас.
  ///
  /// Доля при этом объявляется неизвестной: шаг, о котором нечего сказать,
  /// кроме названия, — это не ноль процентов, а «сколько осталось — неизвестно».
  void message(String text) => report(OperationProgress(message: text, indeterminate: true));

  /// Ждёт вложенную операцию, переливая её прогресс к себе и передавая ей отмену.
  ///
  /// Без этого длинная работа выглядит немой: подключиться к серверу и открыть
  /// архив — это операции провайдеров, и рассказывают о себе они, а показать их
  /// некому, кроме того, кто их запустил. Отмена идёт встречно: прерывают
  /// снаружи, а работает самая вложенная.
  ///
  /// Вопросы вложенной ([ask]) наверх **не** идут. Спросить о ходе работы можно
  /// только там, где для этого есть окно, а вложенная операция о нём не знает;
  /// без слушателей [ask] сам отдаёт вариант по умолчанию, и это честнее, чем
  /// вопрос, повисший в потоке, который никто не читает. Пароль сюда не
  /// относится вовсе: его спрашивает `Credentials` — отдельная служба со своим
  /// окном. По той же причине не идёт вниз и [requestCancel]: вложенная задала
  /// бы вопрос в пустоту, и мягкая отмена молча стала бы жёсткой.
  Future<R> delegate<R>(AsyncOperation<R> inner) async {
    if (isCanceled) {
      // Отменили, пока вложенную только создавали: она уже начала работать, и
      // бросить её как есть нельзя.
      inner.cancel();
      throw const OperationCanceled();
    }

    // Слушаем ход вложенной и пересказываем наружу: она рассказывает о себе,
    // а видно должно быть работу целиком.
    final stopRelay = relayFrom(inner);
    _delegated.add(inner);
    try {
      return await inner.result;
    } finally {
      _delegated.remove(inner);
      // Отписка мгновенная: это Listenable, а не поток.
      stopRelay();
    }
  }

  /// Задаёт вопрос пользователю и ждёт ответа.
  /// Если вопрос никто не слушает, возвращается вариант по умолчанию.
  Future<OperationRequestOption> ask(OperationRequest request) {
    if (_requests.hasListener) {
      _requests.add(request);
      return request.answer;
    }
    // Переходное: по замыслу работа всегда ждёт человека, а спрашивать вправе
    // только та, которую ждут. Пока заявкой владеет команда, а не окно (П6),
    // слушателя действительно может не быть — и тогда берётся то, что нажал бы
    // Enter. Уйдёт вместе с AsyncCommandBase.
    return Future.value(request.enterOption);
  }

  @override
  void cancel() {
    if (_state.isFinished) {
      return;
    }
    _setState(OperationState.canceled);
    // Копия списка: вложенная убирает себя из него сама, а обход идёт по нему же.
    for (final inner in _delegated.toList()) {
      inner.cancel();
    }
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
    _setState(OperationState.processing);
    try {
      final value = await _body(this);
      if (isCanceled) {
        return;
      }
      _setState(OperationState.complete);
      _finish();
      _completer.complete(value);
    } catch (error, stackTrace) {
      if (isCanceled) {
        return;
      }
      _setState(error is OperationCanceled ? OperationState.canceled : OperationState.error);
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

  CompletedOperation.error(Object error) : result = Future.error(error), _state = OperationState.error {
    // Ошибка обязательно должна быть кем-то прочитана, иначе Dart сообщит
    // о необработанной ошибке ещё до того, как её заберёт вызывающий код.
    result.ignore();
  }

  @override
  final Future<T> result;

  OperationState _state = OperationState.complete;

  @override
  OperationState get state => _state;

  @override
  late final OperationStatus status = _TaskOperationStatus()..setState(_state);

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

/// Ход работы, который ведёт [TaskOperation].
///
/// Реализует всю решётку сразу — и это не жадность: одно копирование
/// одновременно и измеримо, и разбито на объекты, и идёт по байтам внутри
/// текущего, и бывает многоэтапным. Чего у него нет прямо сейчас, сказано
/// значением `null`, а не отсутствием типа: «скорость ещё не посчитана» — факт
/// времени выполнения, а не свойство класса.
class _TaskOperationStatus extends ChangeNotifier
    implements
        MeasurableOperationStatus,
        SingleTransferOperationStatus,
        MultipleTransferOperationStatus,
        MultistageOperationStatus,
        InteractiveOperationStatus {
  OperationProgress? lastProgress;

  /// Последний отчёт, в котором объект был назван.
  ///
  /// Итоговый отчёт объекта не называет: работа кончилась, и рассказывать про
  /// «текущий» уже нечего. Но показать пустоту в этот момент — значит убрать
  /// полоску по объекту ровно тогда, когда на результат смотрят. Пустое имя
  /// означает «сказать нечего», а не «объекта не было, забудьте».
  OperationProgress? _lastNamedItem;

  OperationState _state = OperationState.inited;
  UserActionRequest? _request;

  @override
  OperationState get state => _request != null ? OperationState.userActionRequired : _state;

  @override
  String get message => lastProgress?.message ?? '';

  @override
  double? get percentProgress => lastProgress?.percent;

  @override
  double? get speed => lastProgress?.bytesPerSecond;

  @override
  Duration? get remaining => lastProgress?.remaining;

  @override
  String get itemName => _lastNamedItem?.itemName ?? '';

  @override
  int get itemBytesTransferred => _lastNamedItem?.itemBytes ?? 0;

  @override
  int? get itemBytesTotal => _lastNamedItem?.itemTotalBytes;

  @override
  int get bytesTransferred => lastProgress?.bytes ?? 0;

  @override
  int? get bytesTotal => lastProgress?.totalBytes;

  @override
  int get itemsTransferred => lastProgress?.processed ?? 0;

  @override
  int? get itemsTotal => lastProgress?.total;

  @override
  bool get totalIsFinal => lastProgress?.totalIsFinal ?? true;

  /// Этапы известны не заранее: второй появляется, только если в деле оказался
  /// пакетный приёмник. Поэтому список строится из того, что рассказали.
  @override
  List<StageOperationStatus> get stages {
    final progress = lastProgress;
    if (progress == null || !progress.hasStages) {
      return const [];
    }
    return [
      for (var index = 1; index <= progress.stageCount; index++)
        _Stage(index == progress.stage ? progress.stageName : ''),
    ];
  }

  @override
  UserActionRequest? get request => _request;

  void update(OperationProgress value) {
    lastProgress = value;
    if (value.itemName.isNotEmpty) {
      _lastNamedItem = value;
    }
    notifyListeners();
  }

  void setState(OperationState value) {
    _state = value;
    notifyListeners();
  }

  void setRequest(UserActionRequest? value) {
    _request = value;
    notifyListeners();
  }
}

class _Stage implements StageOperationStatus {
  const _Stage(this.name);

  @override
  final String name;
}
