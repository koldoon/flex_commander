import 'async_operation.dart';

/// Ход пакетной операции над объектами: копирования, переноса.
///
/// Считает два числа. Обработанные объекты — простой счётчик, он растёт по мере
/// работы. Общее количество считается **фоном**, параллельно самой работе: обход
/// большого дерева стоит почти столько же, сколько его копирование, и ждать его
/// перед началом незачем. Поэтому общее число сначала неизвестно, потом растёт
/// и лишь в конце становится окончательным — [OperationProgress.totalIsFinal]
/// говорит, что именно сейчас видит пользователь.
///
/// Отдельный случай — источник, обработанный **целиком одним действием**:
/// переименование переносит поддерево разом, пропуск отменяет его разом. Сколько
/// в нём объектов, к этому моменту может быть ещё не посчитано, поэтому такие
/// источники запоминаются и учитываются, как только счёт до них дойдёт.
class TransferProgress {
  TransferProgress(this._operation, this._verb);

  final TaskOperation<void> _operation;

  /// Что происходит: `Copying`, `Moving`.
  final String _verb;

  /// Сколько объектов насчитано в каждом источнике — по мере подсчёта.
  final Map<int, int> _countedSources = {};

  /// Источники, обработанные целиком, но ещё не посчитанные.
  final Set<int> _wholeSources = {};

  int _processed = 0;
  int _total = 0;
  bool _counted = false;
  bool _stopped = false;
  String _current = '';

  int get processed => _processed;

  int get total => _total;

  /// Подсчёт закончился: [total] — окончательное число.
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

  /// Посчитан очередной объект.
  void countOne() {
    _total++;
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
    _report();
  }

  /// В источнике [index] насчитано [count] объектов.
  void sourceCounted(int index, int count) {
    _countedSources[index] = count;
    if (_wholeSources.remove(index)) {
      _processed += count;
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
    _operation.report(OperationProgress(percent: 1, message: 'Done', processed: done, total: done, totalIsFinal: true));
  }

  /// Сообщение уходит на каждое изменение: как часто перерисовываться, решает
  /// тот, кто показывает прогресс (см. `AsyncCommandBase`), — модель не должна
  /// гадать, кто и с какой частотой её слушает.
  void _report() {
    _operation.report(
      OperationProgress(
        message: _current.isEmpty ? '$_verb…' : '$_verb $_current…',
        processed: _processed,
        // Ноль — это не «ничего нет», а «ещё не считали».
        total: _total == 0 && !_counted ? null : _total,
        totalIsFinal: _counted,
      ),
    );
  }
}
