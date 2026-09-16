import 'dart:async';

/// Работа делается не на каждое событие, а когда события кончились.
///
/// **Чем отличается от `Throttle`**, который стоит рядом: тот пропускает первое
/// событие **сразу** — и правильно делает, он про перерисовку. Здесь наоборот:
/// первое событие только заводит накопление. Дело в цене работы. Файловая
/// система на одно осмысленное изменение присылает несколько событий (одно
/// переименование — четыре, распаковка двухсот файлов — четыреста девять,
/// замерено живьём), а работа по событию — чтение целого каталога.
///
/// Поэтому событие здесь — **повод, а не приказ**.
class Settle {
  Settle(this._action, {Duration Function()? quiet, Duration Function()? atMost})
    : _quiet = quiet ?? (() => defaultQuiet),
      _atMost = atMost ?? (() => defaultAtMost);

  /// Сколько тишины считать концом пачки.
  static const Duration defaultQuiet = Duration(milliseconds: 300);

  /// Дольше этого работа не откладывается, сколько бы событий ни шло.
  ///
  /// Без предела распаковка архива в десять минут означала бы десять минут
  /// неподвижного списка: события идут не переставая, и окно тишины не
  /// наступает никогда.
  static const Duration defaultAtMost = Duration(seconds: 2);

  final Future<void> Function() _action;

  /// Способом узнать, а не значением: длительность правят в настройках, и
  /// следующее окно должно идти уже по новому числу.
  final Duration Function() _quiet;
  final Duration Function() _atMost;

  Timer? _timer;

  /// Когда пришло первое событие этой пачки; null — пачки нет.
  DateTime? _since;

  /// Работа идёт прямо сейчас.
  bool _working = false;

  /// Пока работа шла, события были.
  bool _again = false;

  /// Есть ли что отдать: пачка копится или работа ждёт своей очереди.
  bool get pending => _timer != null || _again;

  /// Сообщить о событии.
  void call() {
    // Работа идёт — ждём её конца: два чтения одного каталога разом не нужны
    // никому, а последнее всё равно окажется вернее.
    if (_working) {
      _again = true;
      return;
    }

    final now = DateTime.now();
    final since = _since ??= now;
    final quiet = _quiet();
    final left = _atMost() - now.difference(since);

    _timer?.cancel();
    // Ближе из двух: конец тишины или предел ожидания.
    _timer = Timer(left < quiet ? (left.isNegative ? Duration.zero : left) : quiet, _run);
  }

  /// Забыть накопленное и снять отсчёт.
  ///
  /// Обязательно при разборе: таймер, переживший хозяина, роняет виджет-тест —
  /// и правильно делает, в приложении он пережил бы окно.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _since = null;
    _again = false;
  }

  Future<void> _run() async {
    _timer = null;
    _since = null;
    _working = true;
    try {
      await _action();
    } finally {
      _working = false;
    }

    if (_again) {
      _again = false;
      // Новым окном, а не немедленно: буря, не кончившаяся за время работы, так
      // и остаётся чередой чтений с передышкой, а не гонкой.
      call();
    }
  }
}
