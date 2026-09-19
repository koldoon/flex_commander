import 'dart:async';

/// Ограничитель частоты перерисовки.
///
/// Долгие операции сообщают о каждом своём шаге: копирование мелких файлов и
/// подсчёт размера каталога идут куда быстрее, чем имеет смысл обновлять
/// интерфейс. Модель при этом остаётся честной — она не гадает, кто её слушает,
/// — а частоту выбирает тот, кто показывает результат.
///
/// Первое событие проходит сразу, следующие — не чаще окна. Последнее из
/// отброшенных всё равно доходит, с задержкой: иначе на экране осталось бы
/// предпоследнее состояние.
///
/// **Чем отличается от [Settle]**, который стоит рядом: здесь первое событие
/// проходит **сразу** — это перерисовка, и ждать её незачем. Там наоборот:
/// событие только заводит накопление, потому что работа по нему тяжёлая.
class Throttle {
  Throttle(this._action, {Duration Function()? interval}) : _interval = interval ?? (() => defaultInterval);

  /// Окно по умолчанию: чаще перерисовывать незачем, реже — уже видно глазом.
  static const Duration defaultInterval = Duration(milliseconds: 50);

  final void Function() _action;

  /// Способом узнать, а не значением — как у [Settle].
  ///
  /// Окно бывает непостоянным: у растущего списка оно равно цене его же
  /// перерисовки, а та растёт вместе со списком
  /// (`docs/spec/growing-listing.md`, §3). Спрашивается перед каждым шагом,
  /// поэтому новое окно действует со следующего же события.
  final Duration Function() _interval;

  /// Окно, по которому ограничитель работает сейчас.
  Duration get interval => _interval();

  final Stopwatch _sinceRun = Stopwatch();
  Timer? _pending;

  /// Сообщить об изменении.
  void call() {
    final window = _interval();
    if (_sinceRun.isRunning && _sinceRun.elapsed < window) {
      _pending ??= Timer(window - _sinceRun.elapsed, _run);
      return;
    }
    _run();
  }

  /// Показать немедленно, не дожидаясь окна: работа закончилась.
  void flush() => _run();

  /// Забыть отложенное: результат больше никого не интересует.
  void cancel() {
    _pending?.cancel();
    _pending = null;
    _sinceRun
      ..stop()
      ..reset();
  }

  void _run() {
    _pending?.cancel();
    _pending = null;
    _sinceRun
      ..reset()
      ..start();
    _action();
  }
}
