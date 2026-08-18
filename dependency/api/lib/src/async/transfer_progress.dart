import 'async_operation.dart';

/// Ход пакетной операции над объектами: копирования, переноса, удаления.
///
/// Считает две пары чисел — объекты и байты. Обработанное растёт по мере
/// работы; общее считается **фоном**, параллельно ей: обход большого дерева
/// стоит почти столько же, сколько его копирование, и ждать его перед началом
/// незачем. Поэтому общее сначала неизвестно, потом растёт и лишь в конце
/// становится окончательным — [OperationProgress.totalIsFinal] говорит, что
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

  final TaskOperation<void> _operation;

  /// Что происходит: `Copying`, `Moving`.
  final String _verb;

  final _SpeedWindow _speed;

  /// Сколько объектов и байт насчитано в каждом источнике — по мере подсчёта.
  final Map<int, int> _countedSources = {};
  final Map<int, int> _countedBytes = {};

  /// Источники, обработанные целиком, но ещё не посчитанные.
  final Set<int> _wholeSources = {};

  int _processed = 0;
  int _total = 0;
  int _bytes = 0;
  int _totalBytes = 0;
  bool _counted = false;
  bool _stopped = false;
  String _current = '';

  int get processed => _processed;

  int get total => _total;

  int get bytes => _bytes;

  int get totalBytes => _totalBytes;

  /// Подсчёт закончился: [total] и [totalBytes] — окончательные числа.
  bool get isCounted => _counted;

  /// Работа кончилась — фоновому подсчёту пора остановиться.
  bool get stopped => _stopped;

  /// Начало работы над очередным источником.
  void startSource(String name) {
    _current = name;
    _report();
  }

  /// Обработан очередной объект.
  void advance(String name) {
    _processed++;
    _current = name;
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
    _speed.sample(_bytes);
    _report();
  }

  /// Посчитан очередной объект размером [bytes].
  void countOne(int bytes) {
    _total++;
    if (bytes > 0) {
      _totalBytes += bytes;
    }
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
    _countedSources[index] = count;
    _countedBytes[index] = bytes;
    if (_wholeSources.remove(index)) {
      _processed += count;
      _bytes += bytes;
    }
    _report();
  }

  void countingFinished() {
    _counted = true;
    _report();
  }

  void stop() => _stopped = true;

  /// Работа закончена.
  ///
  /// Счётчики выравниваются: задание выполнено целиком, даже если фоновый
  /// подсчёт к этому моменту не успел дойти до конца — досчитывать его теперь
  /// значило бы обходить дерево ради числа, которое никому уже не нужно.
  void finish() {
    final done = _processed > _total ? _processed : _total;
    final bytes = _bytes > _totalBytes ? _bytes : _totalBytes;
    _operation.report(
      OperationProgress(
        percent: 1,
        message: 'Done',
        processed: done,
        total: done,
        totalIsFinal: true,
        bytes: bytes,
        totalBytes: bytes,
      ),
    );
  }

  /// Сообщение уходит на каждое изменение: как часто перерисовываться, решает
  /// тот, кто показывает прогресс (см. `AsyncCommandBase`), — модель не должна
  /// гадать, кто и с какой частотой её слушает.
  ///
  /// После [stop] не уходит вовсе: работа кончилась, и фоновый подсчёт, который
  /// ещё доскрипывает, не должен дописывать что-то после «Done».
  void _report() {
    if (_stopped) {
      return;
    }
    _operation.report(
      OperationProgress(
        message: _current.isEmpty ? '$_verb…' : '$_verb $_current…',
        processed: _processed,
        // Ноль — это не «ничего нет», а «ещё не считали».
        total: _total == 0 && !_counted ? null : _total,
        totalIsFinal: _counted,
        bytes: _bytes,
        // Задание без байтов (пустые файлы, удаление в корзину) не должно
        // показывать долю по байтам: она была бы неотличима от нуля работы.
        totalBytes: _totalBytes == 0 ? null : _totalBytes,
        bytesPerSecond: _speed.perSecond,
      ),
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
