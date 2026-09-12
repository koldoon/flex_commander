import 'package:fc_api/fc_api.dart';

/// Где сессия побывала и где она в этом ряду стоит сейчас.
///
/// Ведёт себя как история браузера (`docs/spec/session-history.md`, §5): шаг
/// назад сам в историю не пишется, а новый переход после возврата обрезает
/// «вперёд» — ветка, из которой ушли, не хранится.
///
/// Знает только о путях и курсорах: ни каталогов, ни провайдеров, ни чтения.
/// Поэтому её можно проверить целиком, не поднимая ни одной панели.
class SessionHistory {
  SessionHistory({List<PathStep>? steps, int index = 0, required this.limit})
    : _steps = [...?steps],
      _index = steps == null || steps.isEmpty ? -1 : index.clamp(0, steps.length - 1);

  /// Сколько шагов помнит сессия, пока предел не назвали настройкой.
  static const int defaultLimit = 50;

  /// Сколько шагов помнить; спрашивается **каждый раз**, а не берётся при
  /// создании: предел правят в окне настроек, и следующий же переход должен
  /// считаться по новому (`docs/spec/session-history.md`, §7).
  final int Function() limit;

  final List<PathStep> _steps;

  /// Где стоим; −1 — истории нет вовсе.
  int _index;

  List<PathStep> get steps => List.unmodifiable(_steps);

  int get index => _index;

  PathStep? get current => _index < 0 ? null : _steps[_index];

  bool get canGoBack => _index > 0;

  bool get canGoForward => _index >= 0 && _index < _steps.length - 1;

  /// Панель открыла каталог — записываем шаг.
  ///
  /// Возвращает true, если история изменилась: по этому ответу решают, надо ли
  /// рассказывать о себе той стороне.
  bool visit(PathStep step) {
    if (step.isEmpty) {
      return false;
    }

    // То же место подряд шага не добавляет: перечитывание и возврат в тот же
    // каталог — не перемещение. Курсор при этом обновляется: человек мог
    // уйти вглубь и вернуться, встав на другую строку.
    final here = current;
    if (here != null && here.path == step.path) {
      if (here.cursor == step.cursor) {
        return false;
      }
      _steps[_index] = step;
      return true;
    }

    // Новый переход обрезает «вперёд»: помнить два будущих сразу человек всё
    // равно не станет.
    if (_index < _steps.length - 1) {
      _steps.removeRange(_index + 1, _steps.length);
    }
    _steps.add(step);
    _index = _steps.length - 1;
    _trim();
    return true;
  }

  /// Курсор ушёл с места — запомнить его в нынешнем шаге.
  ///
  /// Шаг помнит то имя, на котором стояли **в момент ухода**, а не то, с
  /// которым в каталог вошли: вернуться человек хочет туда, где был.
  void noteCursor(String cursor) {
    final here = current;
    if (here == null || here.cursor == cursor) {
      return;
    }
    _steps[_index] = here.copyWith(cursor: cursor);
  }

  /// Шаг назад; null — идти некуда.
  PathStep? back() => canGoBack ? _steps[--_index] : null;

  /// Шаг вперёд; null — идти некуда.
  PathStep? forward() => canGoForward ? _steps[++_index] : null;

  /// Прыжок к названному шагу — **ход по истории**, а не новый переход:
  /// «вперёд» от этого не обрезается (`docs/spec/session-history.md`, §9).
  ///
  /// null — такого шага нет или это тот, на котором и стоим.
  PathStep? goTo(int index) {
    if (index < 0 || index >= _steps.length || index == _index) {
      return null;
    }
    _index = index;
    return _steps[index];
  }

  /// Настройки сессии: шаги и номер нынешнего.
  ({List<PathStep> steps, int index}) get saved => (steps: List.of(_steps), index: _index < 0 ? 0 : _index);

  /// Вытеснить самое старое, если шагов стало больше предела.
  ///
  /// Старое, а не новое: «назад» на десять шагов нужнее, чем память о том, где
  /// мы были в позапрошлом году. Нынешний шаг при этом не теряется — он
  /// последний, и до него очередь дойдёт только при пределе меньше единицы.
  void _trim() {
    final allowed = limit();
    if (allowed <= 0) {
      return;
    }
    while (_steps.length > allowed) {
      _steps.removeAt(0);
      _index--;
    }
    if (_index < 0) {
      _index = _steps.isEmpty ? -1 : 0;
    }
  }
}
