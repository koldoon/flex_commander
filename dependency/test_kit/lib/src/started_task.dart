import 'package:fc_api/fc_api.dart';

/// Работа, заведённая сразу.
///
/// В приложении «создать» и «запустить» разведены нарочно: работа успевает
/// попасть в очередь, а окно — подписаться на её ход. Тесту, который проверяет
/// само тело, эта пауза ни к чему, и здесь она свёрнута обратно в один шаг.
///
/// Параметров у такой работы нет: те, что проверяют передачу параметров,
/// пользуются обычным [TaskOperation] и зовут [Operation.start] сами.
TaskOperation<void, R> startedTask<R>(Future<R> Function(TaskOperation<void, R> op) body) =>
    TaskOperation<void, R>((op, _) => body(op))..start(null);
