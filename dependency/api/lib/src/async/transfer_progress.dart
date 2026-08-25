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
  TransferProgress(this._operation, {DateTime Function() clock = DateTime.now}) : _speed = _SpeedWindow(clock);

  final TaskOperation<Object?, void> _operation;

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

  /// Источник задания, над которым идёт работа: объект под курсором или
  /// очередной из помеченных.
  String _current = '';

  /// Объекты, которые обрабатываются **прямо сейчас**.
  ///
  /// Их бывает несколько: мелкие файлы уходят на сервер не по одному, иначе
  /// каждый ждал бы своей очереди, а до него — ответа на предыдущий.
  ///
  /// Наружу показывается самый ранний из живых и держится, пока не кончится.
  /// Показывать последний начатый значило бы менять строку по десять раз в
  /// секунду: прочитать её было бы нельзя.
  final Map<int, _Item> _items = {};
  int _nextItem = 0;

  /// Последний закрытый — он остаётся на виду, пока не начался следующий.
  ///
  /// Пустая строка в конце работы убрала бы полосу по объекту ровно тогда,
  /// когда на неё смотрят, а между файлами она бы мигала.
  _Item? _finished;

  /// Чем работа занята вместо переноса; пустая строка — переносом и занята.
  String _chore = '';

  _Item? get _shown {
    if (_items.isEmpty) {
      return _finished;
    }
    var earliest = _items.keys.first;
    for (final token in _items.keys) {
      if (token < earliest) {
        earliest = token;
      }
    }
    return _items[earliest];
  }

  int get processed => _processed;

  int get total => _total;

  int get bytes => _bytes;

  int get totalBytes => _totalBytes;

  /// Что обрабатывается прямо сейчас.
  String get item => _chore.isNotEmpty ? _chore : (_shown?.name ?? '');

  int get itemBytes => _chore.isNotEmpty ? 0 : (_shown?.bytes ?? 0);

  int? get itemTotalBytes => _chore.isNotEmpty ? null : _shown?.totalBytes;

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

  /// Уборка по дороге: чем работа занята сейчас, если это не перенос.
  ///
  /// Перезапись приёмника сперва убирает то, что там лежало, а перенос — то,
  /// что осталось в источнике. В счётчиках задания эти объекты не считаются:
  /// они не наши. Но молчать о них нельзя — по сети уборка каталога идёт
  /// минутами, и окно всё это время выглядело бы зависшим.
  ///
  /// Показывается там же, где текущий объект: источник задания при этом не
  /// меняется — убирают-то ради него.
  void chore(String name) {
    _chore = name;
    _report();
  }

  /// Уборка кончилась: дальше снова видно сам перенос.
  void choreDone() {
    if (_chore.isEmpty) {
      return;
    }
    _chore = '';
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
  /// Возвращает метку: по ней объекту засчитывают байты и по ней же его
  /// закрывают. Без метки не обойтись — объектов в работе бывает несколько.
  int startItem(String name, {int? bytes}) {
    final token = _nextItem++;
    _items[token] = _Item(name, bytes != null && bytes >= 0 ? bytes : null);
    // Место занято новым: прежний своё отстоял.
    _finished = null;
    _report();
    return token;
  }

  /// Объект пройден: его собственный счёт больше ничего не значит.
  ///
  /// Последний закрытый остаётся на виду, пока не начался следующий: пустая
  /// строка в конце работы убрала бы полосу ровно тогда, когда на неё смотрят
  /// (см. `dialog-run-phase.md` — там же про хвост работы).
  void finishItem(int token) {
    final item = _items.remove(token);
    if (item == null) {
      return;
    }
    if (_items.isEmpty) {
      _finished = item;
    }
    _report();
  }

  /// Обработан очередной объект.
  ///
  /// Имени не берёт: [_current] — это **источник задания**, тот самый объект,
  /// что был под курсором или в списке помеченных. Он не меняется, пока работа
  /// идёт вглубь: копируется каталог — в строке `Item` весь этот час он и
  /// стоит, а по его содержимому бежит строка `File`.
  void advance() {
    _processed++;
    _report();
  }

  /// Перенесены очередные байты.
  ///
  /// Зовётся по куску потока, а не по файлу: внутри большого файла тоже должно
  /// быть видно движение.
  /// [item] — метка объекта, которому эти байты принадлежат; null — байты
  /// задания, ничьи в отдельности (так их считает перепаковка архива).
  void advanceBytes(int bytes, [int? item]) {
    if (bytes <= 0) {
      return;
    }
    _bytes += bytes;
    if (item != null) {
      _items[item]?.bytes += bytes;
    }
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
      // Имя — и только имя: чем занята работа, сказано в заголовке окна, а
      // подпись строки говорит, что это за имя. Повторять то и другое внутри
      // строки значит оставить меньше места самому имени.
      message: _current,
      stage: _stage,
      stageCount: _stageCount,
      stageName: _stageName,
      indeterminate: !_stageSized,
      itemName: item,
      itemBytesTransferred: itemBytes,
      itemBytesTotal: itemTotalBytes,
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

/// Объект в работе: имя, сколько его уже прошло и сколько в нём всего.
class _Item {
  _Item(this.name, this.totalBytes);

  final String name;
  final int? totalBytes;
  int bytes = 0;
}
