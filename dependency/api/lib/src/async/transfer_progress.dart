import 'async_operation.dart';

/// Ход пакетной операции над объектами: копирования, переноса, удаления.
///
/// Считает две пары чисел — объекты и байты. Обработанное растёт по мере
/// работы; общее считается **фоном**, параллельно ей: обход большого дерева
/// стоит почти столько же, сколько его копирование, и ждать его перед началом
/// незачем. Поэтому общее сначала неизвестно, потом растёт и лишь в конце
/// становится окончательным — [MultipleTransferOperationStatus.totalIsFinal] говорит, что
/// именно сейчас видит пользователь.
///
/// Байты нужны там, где объекты ничего не описывают: копирование одного файла
/// на четыре гигабайта — это «0 из 1» до самого конца. По ним же считается
/// скорость и оценка времени, и считаются они здесь, а не в провайдере:
/// провайдер видит один объект, а не всё задание.
///
/// Отдельный случай — источник, обработанный **целиком одним действием**:
/// переименование переносит поддерево разом, пропуск отменяет его разом. Сколько
/// в нём объектов и байт, к этому моменту может быть ещё не посчитано, поэтому
/// такие источники запоминаются и учитываются, как только счёт до них дойдёт.
class TransferProgress {
  TransferProgress(this._operation, this._verb, {DateTime Function() clock = DateTime.now})
    : _speed = _SpeedWindow(clock);

  final TaskOperation<Object?, void> _operation;

  /// Что происходит: `Copying`, `Moving`.
  final String _verb;

  final _SpeedWindow _speed;

  /// Сколько объектов и байт насчитано в каждом источнике — по мере подсчёта.
  final Map<int, int> _countedSources = {};
  final Map<int, int> _countedBytes = {};

  /// Источники, обработанные целиком, но ещё не посчитанные.
  final Set<int> _wholeSources = {};

  /// Плечо работы: который идёт, сколько всего и чем занято.
  int _stage = 0;
  int _stageCount = 0;
  String _stageName = '';
  bool _stageSized = true;

  int _processed = 0;
  int _total = 0;
  int _bytes = 0;
  int _totalBytes = 0;
  bool _counted = false;
  bool _stopped = false;
  String _current = '';

  /// Объект, который обрабатывается прямо сейчас, и сколько его уже прошло.
  String _item = '';
  int _itemBytes = 0;
  int? _itemTotalBytes;

  int get processed => _processed;

  int get total => _total;

  int get bytes => _bytes;

  int get totalBytes => _totalBytes;

  /// Что обрабатывается прямо сейчас.
  String get item => _item;

  int get itemBytes => _itemBytes;

  int? get itemTotalBytes => _itemTotalBytes;

  /// Подсчёт закончился: [total] и [totalBytes] — окончательные числа.
  bool get isCounted => _counted;

  /// Работа кончилась — фоновому подсчёту пора остановиться.
  bool get stopped => _stopped;

  /// Начинается очередное плечо работы.
  ///
  /// Плечи заводит тот, кто ведёт работу, и только там, где второе плечо
  /// действительно долгое: упаковка и передача архива, запись в архив и его
  /// пересборка. У обычного копирования плеч нет, и окно о них молчит.
  ///
  /// [sized] — известно ли, сколько в этом плече работы. Неизвестно (пересборка
  /// архива) — доля не показывается вовсе: полоса, замершая на ста процентах,
  /// выглядит как зависшая программа.
  void beginStage(String name, {required int index, required int count, bool sized = true}) {
    _stage = index;
    _stageCount = count;
    _stageName = name;
    _stageSized = sized;
    _report();
  }

  /// Начало работы над очередным источником.
  void startSource(String name) {
    _current = name;
    _report();
  }

  /// Начался очередной объект: [bytes] — сколько в нём, null — неизвестно.
  ///
  /// Отсюда и берётся ход по текущему объекту: без него большой файл выглядит
  /// как остановка — общий счёт по нему не двигается до самого конца.
  void startItem(String name, {int? bytes}) {
    _item = name;
    _itemBytes = 0;
    _itemTotalBytes = bytes != null && bytes >= 0 ? bytes : null;
    _report();
  }

  /// Обработан очередной объект.
  void advance(String name) {
    _processed++;
    _current = name;
    // Объект пройден: его собственный счёт больше ничего не значит.
    _item = '';
    _itemBytes = 0;
    _itemTotalBytes = null;
    _report();
  }

  /// Перенесены очередные байты.
  ///
  /// Зовётся по куску потока, а не по файлу: внутри большого файла тоже должно
  /// быть видно движение.
  void advanceBytes(int bytes) {
    if (bytes <= 0) {
      return;
    }
    _bytes += bytes;
    _itemBytes += bytes;
    _speed.sample(_bytes);
    _report();
  }

  /// Посчитан очередной объект размером [bytes].
  void countOne(int bytes) {
    if (_stopped) {
      return;
    }
    _total++;
    if (bytes > 0) {
      _totalBytes += bytes;
    }
    _report();
  }

  /// Работы прибавилось на [bytes] байт — без нового объекта.
  ///
  /// Так учитывается второе плечо работы, размер которого до времени неизвестен:
  /// упаковка сперва читает исходные байты, а потом отдаёт приёмнику готовый
  /// архив, и сколько в нём байт, видно только когда он собран.
  void countBytes(int bytes) {
    if (bytes <= 0 || _stopped) {
      return;
    }
    _totalBytes += bytes;
    _report();
  }

  /// Источник обработан целиком одним действием.
  void sourceDoneWholly(int index) {
    final counted = _countedSources[index];
    if (counted == null) {
      // Досчитают — тогда и учтётся.
      _wholeSources.add(index);
      return;
    }
    _processed += counted;
    _bytes += _countedBytes[index] ?? 0;
    _report();
  }

  /// В источнике [index] насчитано [count] объектов на [bytes] байт.
  void sourceCounted(int index, int count, int bytes) {
    if (_stopped) {
      return;
    }
    _countedSources[index] = count;
    _countedBytes[index] = bytes;
    if (_wholeSources.remove(index)) {
      _processed += count;
      _bytes += bytes;
    }
    _report();
  }

  void countingFinished() {
    if (_stopped) {
      return;
    }
    _counted = true;
    _report();
  }

  /// Работа кончилась — фоновому подсчёту пора остановиться.
  ///
  /// Останавливается именно **подсчёт**, а не рассказ о ходе работы: после
  /// этого может начаться последнее плечо — пересборка архива, — и молчать о
  /// нём нельзя, иначе окно замрёт на «готово», пока идёт работа.
  void stop() => _stopped = true;

  /// Работа закончена.
  ///
  /// Счётчики выравниваются: задание выполнено целиком, даже если фоновый
  /// подсчёт к этому моменту не успел дойти до конца — досчитывать его теперь
  /// значило бы обходить дерево ради числа, которое никому уже не нужно.
  void finish() {
    // Этапы кончились вместе с работой: «Done» ни к какому плечу не относится.
    _stage = 0;
    _stageCount = 0;
    _stageName = '';
    _stageSized = true;
    final done = _processed > _total ? _processed : _total;
    final bytes = _bytes > _totalBytes ? _bytes : _totalBytes;
    _operation.report(
      percent: 1,
      message: 'Done',
      itemsTransferred: done,
      itemsTotal: done,
      bytesTransferred: bytes,
      bytesTotal: bytes,
    );
  }

  /// Сообщение уходит на каждое изменение: как часто перерисовываться, решает
  /// тот, кто показывает прогресс (см. `FcAsyncRun`), — модель не должна
  /// гадать, кто и с какой частотой её слушает.
  void _report() {
    _operation.report(
      message: _current.isEmpty ? '$_verb…' : '$_verb $_current…',
      stage: _stage,
      stageCount: _stageCount,
      stageName: _stageName,
      indeterminate: !_stageSized,
      itemName: _item,
      itemBytesTransferred: _itemBytes,
      itemBytesTotal: _itemTotalBytes,
      itemsTransferred: _processed,
      // Ноль — это не «ничего нет», а «ещё не считали».
      itemsTotal: _total == 0 && !_counted ? null : _total,
      totalIsFinal: _counted,
      bytesTransferred: _bytes,
      // Задание без байтов (пустые файлы, удаление в корзину) не должно
      // показывать долю по байтам: она была бы неотличима от нуля работы.
      bytesTotal: _totalBytes == 0 ? null : _totalBytes,
      speed: _speed.perSecond,
    );
  }
}

/// Скорость по скользящему окну.
///
/// Мгновенная скакала бы на каждом куске, а средняя за всё время не поспевала
/// бы за изменением: сеть просела — это должно быть видно сразу, а не размыто
/// по всей операции.
class _SpeedWindow {
  _SpeedWindow(this._clock);

  final DateTime Function() _clock;

  /// За какое время считаем и как часто берём отсчёты.
  static const Duration window = Duration(seconds: 3);
  static const Duration interval = Duration(milliseconds: 200);

  final List<(DateTime, int)> _samples = [];

  void sample(int bytes) {
    final now = _clock();
    if (_samples.isNotEmpty && now.difference(_samples.last.$1) < interval) {
      return;
    }

    _samples.add((now, bytes));
    _samples.removeWhere((sample) => now.difference(sample.$1) > window);
  }

  /// Байт в секунду; null — отсчётов слишком мало, чтобы не соврать.
  double? get perSecond {
    if (_samples.length < 2) {
      return null;
    }

    final first = _samples.first;
    final last = _samples.last;
    final seconds = last.$1.difference(first.$1).inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) {
      return null;
    }
    return (last.$2 - first.$2) / seconds;
  }
}
