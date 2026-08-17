import 'dart:async';

/// Ограничитель частоты перерисовки.
///
/// Долгие операции сообщают о каждом своём шаге: копирование мелких файлов и
/// подсчёт размера каталога идут куда быстрее, чем имеет смысл обновлять
/// интерфейс. Модель при этом остаётся честной — она не гадает, кто её слушает,
/// — а частоту выбирает тот, кто показывает результат.
///
/// Первое событие проходит сразу, следующие — не чаще [interval]. Последнее из
/// отброшенных всё равно доходит, с задержкой: иначе на экране осталось бы
/// предпоследнее состояние.
class Throttle {
  Throttle(this._action, {this.interval = const Duration(milliseconds: 50)});

  final void Function() _action;

  final Duration interval;

  final Stopwatch _sinceRun = Stopwatch();
  Timer? _pending;

  /// Сообщить об изменении.
  void call() {
    if (_sinceRun.isRunning && _sinceRun.elapsed < interval) {
      _pending ??= Timer(interval - _sinceRun.elapsed, _run);
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
