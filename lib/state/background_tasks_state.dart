import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

/// Список работ, ушедших в фон с этой панели, — содержимое статусной области.
///
/// Спецификация — `docs/spec/background-operations.md`.
///
/// Состоянием области, а не полосой в шелле: у областей есть фокус и клавиши,
/// и ровно этого списку не хватало. Всё остальное — рама, курсор, `Cmd-B` —
/// следствия.
class BackgroundTasksState extends ChangeNotifier implements ViewportState {
  BackgroundTasksState({required this.owner, required this.operations}) {
    operations.addListener(_onRuns);
  }

  /// Под какой панелью стоит список. Позицией панели, а не её статусной
  /// области: работы принадлежат стороне, и спрашивают их так же.
  final ViewportPosition owner;

  final Operations operations;

  /// Работы этой стороны — в том порядке, в каком их показывают.
  List<OperationRun> get runs => operations.at(owner);

  /// Строка под курсором. Пусто — работ не осталось.
  OperationRun? get current {
    final all = runs;
    return all.isEmpty ? null : all[_cursor.clamp(0, all.length - 1)];
  }

  /// Номер строки под курсором; всегда внутри списка.
  int get cursor {
    final length = runs.length;
    return length == 0 ? 0 : _cursor.clamp(0, length - 1);
  }

  set cursor(int value) {
    final length = runs.length;
    final next = length == 0 ? 0 : value.clamp(0, length - 1);
    if (next == _cursor) {
      return;
    }
    _cursor = next;
    notifyListeners();
  }

  int _cursor = 0;

  /// Системный фокус не нужен: поля ввода внутри нет, а нажатия разбирает
  /// ранний обработчик — так же, как у панели.
  @override
  bool get takesKeyboard => false;

  @override
  void close() {
    operations.removeListener(_onRuns);
    dispose();
  }

  /// Работ стало больше или меньше — список перерисовывается, а курсор
  /// подтягивается в границы: забыли ту, что была последней, и он обязан
  /// остаться на строке, а не за ней.
  void _onRuns() {
    final length = runs.length;
    if (length > 0 && _cursor > length - 1) {
      _cursor = length - 1;
    }
    notifyListeners();
  }
}
