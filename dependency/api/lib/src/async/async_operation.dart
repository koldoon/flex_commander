import 'dart:async';

import 'package:flutter/foundation.dart';

import 'operation_request.dart';
import 'operation_status.dart';

/// Операция отменена вызовом [AsyncOperation.cancel].
class OperationCanceled implements Exception {
  const OperationCanceled();

  @override
  String toString() => 'OperationCanceled';
}

/// Длительная работа: параметры на входе, результат на выходе.
///
/// От голого [Future] отличается тремя вещами, без которых не обойтись
/// файловому менеджеру: работу можно отменить, она умеет сообщать о ходе дела
/// и задавать вопросы (перезаписать? пропустить?) не прерываясь.
///
/// **Создать и запустить — разные действия.** Созданная работа не начата: на
/// неё можно спокойно подписаться, положить её в очередь, показать строкой
/// «ждёт». Пока никто не позвал [start], не случилось ничего.
///
/// **Вход — только данные.** Ни приложения, ни областей, ни панелей в типе [P]
/// быть не должно: живое состояние читает команда, до запуска, а работа
/// получает снимок. Иначе фоновое копирование сломается в тот день, когда
/// панель выйдет из архива. Это проверяет доктринальный тест.
abstract class Operation<P, R> {
  OperationState get state;

  /// Ход работы — объект, и другого канала нет.
  ///
  /// Что именно про работу известно — доля, скорость, байты, этапы, — говорят
  /// подтипы [OperationStatus]: работа объявляет о себе тем, что реализует.
  /// Читается он всегда, подписка не обязательна; подписавшийся получает
  /// уведомление на каждый отчёт.
  ///
  /// Потока событий рядом с ним больше нет. Был — и оказался вторым
  /// источником правды о том же самом: событие можно пропустить, объект нельзя,
  /// и разъехаться им было нечем только потому, что поток питался из объекта.
  OperationStatus get status;

  /// Результат. Завершается ошибкой [FsError] или [OperationCanceled].
  ///
  /// Отдельно от [start], а не его возвращаемым значением: запускает работу
  /// один — очередь, окно, команда, — а ждать её вправе кто угодно.
  Future<R> get result;

  /// Вопросы пользователю. Пустой поток у работ, которые ничего не спрашивают.
  Stream<OperationRequest> get requests;

  /// Заводит работу с этими данными.
  ///
  /// Второй раз ничего не делает: результат у работы один, и переиграть его
  /// нельзя. Нужна ещё одна такая же — создайте ещё одну.
  void start(P params);

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

/// Завести работу и дождаться её — одним выражением.
///
/// Это не второй способ запуска, а тот же [Operation.start] с ожиданием следом:
/// подавляющему большинству мест разделять «создать» и «запустить» незачем —
/// оно нужно очереди, которая ждёт своей очереди, и окну, которое подписывается
/// раньше запуска.
extension StartAndWait<P, R> on Operation<P, R> {
  Future<R> run(P params) {
    start(params);
    return result;
  }
}

/// Базовая реализация [Operation] для работ, выполняемых в текущем изоляте.
/// Тело получает саму работу — чтобы сообщать о ходе дела, задавать вопросы и
/// проверять отмену, — и её параметры.
class TaskOperation<P, R> implements Operation<P, R> {
  /// Создаёт работу, **не** начиная её: тело ждёт [start].
  ///
  /// Раньше тело стартовало следующим шагом цикла событий, и на этом держался
  /// негласный уговор — подписывайтесь строкой ниже, иначе первые события и
  /// первый вопрос пройдут мимо. Уговора больше нет: создал, подписался,
  /// запустил.
  TaskOperation(this._body);

  final Future<R> Function(TaskOperation<P, R> op, P params) _body;

  final Completer<R> _completer = Completer<R>();
  final StreamController<OperationRequest> _requests = StreamController<OperationRequest>.broadcast();

  OperationState _state = OperationState.inited;

  @override
  OperationState get state => _state;

  @override
  late final OperationStatus status = _status;

  final _TaskOperationStatus _status = _TaskOperationStatus();

  @override
  Future<R> get result => _completer.future;

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

  /// Вложенные работы, которые идут прямо сейчас.
  ///
  /// Список, а не одна ссылка: тело зовёт [delegate] из разных мест — разбор
  /// пути рекурсивен, — и вложенных по дороге может оказаться несколько.
  /// Прерывают всегда снаружи, а работает самая вложенная, и добраться до неё
  /// можно только по такому списку.
  final List<Operation<Object?, Object?>> _delegated = [];

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
  VoidCallback relayFrom(Operation<Object?, Object?> source) {
    final status = source.status;

    void relay() {
      final computable = status is ComputableOperationStatus ? status : null;
      final measurable = status is MeasurableOperationStatus ? status : null;
      final single = status is SingleTransferOperationStatus ? status : null;
      final multiple = status is MultipleTransferOperationStatus ? status : null;
      final staged = status is MultistageOperationStatus ? status : null;
      final stages = staged?.stages ?? const <StageOperationStatus>[];
      final current = stages.indexWhere((stage) => stage.name.isNotEmpty);

      report(
        message: status.message,
        percent: computable?.percentProgress,
        itemsTransferred: multiple?.itemsTransferred ?? 0,
        itemsTotal: multiple?.itemsTotal,
        totalIsFinal: multiple?.totalIsFinal ?? true,
        bytesTransferred: multiple?.bytesTransferred ?? 0,
        bytesTotal: multiple?.bytesTotal,
        speed: measurable?.speed,
        itemName: single?.itemName ?? '',
        itemBytesTransferred: single?.itemBytesTransferred ?? 0,
        itemBytesTotal: single?.itemBytesTotal,
        stage: current < 0 ? 0 : current + 1,
        stageCount: stages.length,
        stageName: current < 0 ? '' : stages[current].name,
      );
    }

    status.addListener(relay);
    relay();
    return () => status.removeListener(relay);
  }

  /// Рассказывает о ходе работы.
  ///
  /// Отчёт **целиком**: что не названо, то и сброшено. Так и было со времён
  /// отдельного объекта-отчёта — накапливает состояние тот, кто ведёт работу
  /// ([TransferProgress]), а не статус.
  ///
  /// Имена — те же, какими ход работы читают: подтипы [OperationStatus] и
  /// отчёт говорят на одном языке, и переводить между ними больше не нужно.
  void report({
    String message = '',
    double? percent,
    bool indeterminate = false,
    int itemsTransferred = 0,
    int? itemsTotal,
    bool totalIsFinal = true,
    int bytesTransferred = 0,
    int? bytesTotal,
    double? speed,
    String itemName = '',
    int itemBytesTransferred = 0,
    int? itemBytesTotal,
    int stage = 0,
    int stageCount = 0,
    String stageName = '',
  }) {
    if (_state.isFinished) {
      // Отчёт вложенной операции, доехавший после конца работы: рассказывать
      // про шаг, которого уже не было, незачем.
      return;
    }
    _status.update(
      message: message,
      percent: percent,
      indeterminate: indeterminate,
      itemsTransferred: itemsTransferred,
      itemsTotal: itemsTotal,
      totalIsFinal: totalIsFinal,
      bytesTransferred: bytesTransferred,
      bytesTotal: bytesTotal,
      speed: speed,
      itemName: itemName,
      itemBytesTransferred: itemBytesTransferred,
      itemBytesTotal: itemBytesTotal,
      stage: stage,
      stageCount: stageCount,
      stageName: stageName,
    );
  }

  /// Веха: чем работа занята сейчас.
  ///
  /// Доля при этом объявляется неизвестной: шаг, о котором нечего сказать,
  /// кроме названия, — это не ноль процентов, а «сколько осталось — неизвестно».
  void message(String text) => report(message: text, indeterminate: true);

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
  Future<R2> delegate<Q, R2>(Operation<Q, R2> inner, Q params) async {
    if (isCanceled) {
      // Отменили, пока вложенную только создавали. Запускать её теперь незачем.
      throw const OperationCanceled();
    }

    // Слушаем ход вложенной и пересказываем наружу: она рассказывает о себе,
    // а видно должно быть работу целиком. Подписка до запуска — потому запуск
    // и отделён от создания.
    final stopRelay = relayFrom(inner);
    _delegated.add(inner);
    try {
      inner.start(params);
      return await inner.result;
    } finally {
      _delegated.remove(inner);
      // Отписка мгновенная: это Listenable, а не поток.
      stopRelay();
    }
  }

  /// Задаёт вопрос пользователю и ждёт ответа.
  /// Если вопрос никто не слушает, возвращается вариант по умолчанию.
  /// [stillNeeded] — нужен ли ещё этот вопрос, когда до него дошла очередь.
  /// Ответ «…все» на предыдущий обычно снимает и все следующие: человек сказал
  /// «пропустить все» один раз, и спрашивать его о том же ещё десять раз —
  /// издевательство. Такой вопрос не показывается вовсе, а вместо ответа
  /// берётся [OperationRequest.enterOption].
  Future<OperationRequestOption> ask(OperationRequest request, {bool Function()? stillNeeded}) {
    // Спрашивают **по одному**. Работа идёт не в один поток: файлы переносятся
    // разом, и вопрос — «уже существует», «ссылку сохранить нечем» — может
    // подняться у нескольких сразу. Окно показывает один вопрос; остальные без
    // очереди повисли бы навсегда, а с ними и вся работа, дошедшая до конца по
    // счётчикам.
    final ahead = _asked;
    final mine = Completer<void>();
    _asked = mine.future;
    return ahead
        .then((_) {
          if (stillNeeded != null && !stillNeeded()) {
            return Future.value(request.enterOption);
          }
          return _ask(request);
        })
        .whenComplete(mine.complete);
  }

  /// Очередь вопросов: следующий поднимается, когда ответили на предыдущий.
  Future<void> _asked = Future<void>.value();

  Future<OperationRequestOption> _ask(OperationRequest request) {
    if (_requests.hasListener) {
      // Работа встала: об этом обязан узнать не только тот, кто её слушает, но
      // и статусная область — там у полоски появляется кнопка «нужен ответ».
      _status.setRequest(request);
      unawaited(request.answer.whenComplete(() => _status.setRequest(null)));
      _requests.add(request);
      return request.answer;
    }
    // Слушать некому — работу запустили без окна: сценарием, привязкой с
    // готовыми значениями, тестом. Ждать в этом случае значило бы повиснуть
    // навсегда и молча, поэтому берётся то, что нажал бы Enter.
    //
    // Это и есть правило «спрашивать вправе только та работа, которую ждут»,
    // выраженное безопасно: не запретом спрашивать, а ответом по умолчанию.
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

  @override
  void start(P params) {
    if (_state != OperationState.inited) {
      // Уже запускали: результат у работы один, и переиграть его нельзя.
      return;
    }
    _setState(OperationState.pending);
    unawaited(_run(params));
  }

  Future<void> _run(P params) async {
    if (isCanceled) {
      // Отменили ещё до старта.
      return;
    }
    _setState(OperationState.processing);
    try {
      final value = await _body(this, params);
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
    _requests.close();
  }
}

/// Уже завершённая работа. Удобна для заглушек и тестов: [start] ей ничего не
/// добавляет — всё уже случилось.
class CompletedOperation<P, R> implements Operation<P, R> {
  CompletedOperation(R value) : result = Future.value(value);

  CompletedOperation.error(Object error) : result = Future.error(error), _state = OperationState.error {
    // Ошибка обязательно должна быть кем-то прочитана, иначе Dart сообщит
    // о необработанной ошибке ещё до того, как её заберёт вызывающий код.
    result.ignore();
  }

  @override
  final Future<R> result;

  OperationState _state = OperationState.complete;

  @override
  OperationState get state => _state;

  @override
  late final OperationStatus status = _TaskOperationStatus()..setState(_state);

  @override
  Stream<OperationRequest> get requests => const Stream.empty();

  /// Запускать нечего: всё уже случилось.
  @override
  void start(P params) {}

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
  /// Ход работы — плоские поля, а не последний отчёт: отчёт был событием, а
  /// это состояние. Что не названо в очередном отчёте, здесь сбрасывается.
  @override
  String message = '';

  double? _percent;
  bool _indeterminate = false;

  @override
  double? speed;

  @override
  int itemsTransferred = 0;

  @override
  int? itemsTotal;

  @override
  bool totalIsFinal = true;

  @override
  int bytesTransferred = 0;

  @override
  int? bytesTotal;

  /// Текущий объект: имя и его собственный счёт.
  ///
  /// Держатся отдельно от остального, потому что переживают отчёт, в котором
  /// объект не назван. Итоговый отчёт его и не называет: работа кончилась, и
  /// рассказывать про «текущий» уже нечего, — но показать пустоту в этот момент
  /// значит убрать полоску по объекту ровно тогда, когда на результат смотрят.
  /// Пустое имя означает «сказать нечего», а не «объекта не было, забудьте».
  @override
  String itemName = '';

  @override
  int itemBytesTransferred = 0;

  @override
  int? itemBytesTotal;

  int _stage = 0;
  int _stageCount = 0;
  String _stageName = '';

  OperationState _state = OperationState.inited;
  UserActionRequest? _request;

  @override
  OperationState get state => _request != null ? OperationState.userActionRequired : _state;

  /// 0.0…1.0 или null, если доля неизвестна.
  ///
  /// Байты честнее объектов везде, где они известны: копирование одного файла
  /// на четыре гигабайта — это «0 из 1» до самого конца.
  @override
  double? get percentProgress {
    if (_indeterminate) {
      return null;
    }
    if (_percent != null) {
      return _percent;
    }

    final size = bytesTotal;
    if (size != null && size > 0) {
      return (bytesTransferred / size).clamp(0.0, 1.0);
    }

    final count = itemsTotal;
    if (count == null || count <= 0) {
      return null;
    }
    // Пока идёт подсчёт, обработанных может оказаться больше, чем насчитано:
    // доля всё равно не должна выходить за единицу.
    return (itemsTransferred / count).clamp(0.0, 1.0);
  }

  /// Сколько ещё ждать; null — считать не из чего.
  ///
  /// Пока подсчёт не закончен ([totalIsFinal]), это оценка по нижней границе:
  /// работы окажется больше, а не меньше.
  @override
  Duration? get remaining {
    final rate = speed;
    final size = bytesTotal;
    if (rate == null || rate <= 0 || size == null || size <= bytesTransferred) {
      return null;
    }
    return Duration(seconds: ((size - bytesTransferred) / rate).round());
  }

  /// Этапы известны не заранее: второй появляется, только если в деле оказался
  /// пакетный приёмник. Поэтому список строится из того, что рассказали.
  @override
  List<StageOperationStatus> get stages {
    if (_stageCount <= 1 || _stage <= 0) {
      return const [];
    }
    return [for (var index = 1; index <= _stageCount; index++) _Stage(index == _stage ? _stageName : '')];
  }

  @override
  UserActionRequest? get request => _request;

  void update({
    required String message,
    required double? percent,
    required bool indeterminate,
    required int itemsTransferred,
    required int? itemsTotal,
    required bool totalIsFinal,
    required int bytesTransferred,
    required int? bytesTotal,
    required double? speed,
    required String itemName,
    required int itemBytesTransferred,
    required int? itemBytesTotal,
    required int stage,
    required int stageCount,
    required String stageName,
  }) {
    this.message = message;
    _percent = percent;
    _indeterminate = indeterminate;
    this.itemsTransferred = itemsTransferred;
    this.itemsTotal = itemsTotal;
    this.totalIsFinal = totalIsFinal;
    this.bytesTransferred = bytesTransferred;
    this.bytesTotal = bytesTotal;
    this.speed = speed;
    // Названный объект переживает отчёт, в котором о нём молчат.
    if (itemName.isNotEmpty) {
      this.itemName = itemName;
      this.itemBytesTransferred = itemBytesTransferred;
      this.itemBytesTotal = itemBytesTotal;
    }
    _stage = stage;
    _stageCount = stageCount;
    _stageName = stageName;
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
