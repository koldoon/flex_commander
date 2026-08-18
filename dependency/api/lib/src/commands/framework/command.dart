/// Работа, которую можно выполнить.
///
/// Всё, что фреймворк требует от команды: уметь выполниться и сказать, когда
/// закончила. Асинхронность выражена самим `Future` — в референсе
/// (`AsyncCommand` из Spicelib) для этого были события `complete`/`error` и
/// признак `active`, а в Dart их роль играет возвращаемое значение: завершение
/// future — это завершение команды, брошенное исключение — ошибка.
abstract interface class Command {
  Future<void> execute();
}

/// Команда, которой есть что передать дальше.
///
/// Результат складывается в [CommandData] составной команды, и следующие
/// команды достают его по типу: так одна команда узнаёт, что сделала
/// предыдущая, не зная о ней ничего.
abstract interface class ResultCommand<T extends Object> implements Command {
  /// Что получилось; null — пока не выполнялась или результата нет.
  T? get result;
}

/// Команда, работу которой можно прервать.
///
/// Отмена — просьба, а не выключатель: команда останавливается там, где это
/// безопасно, и завершает свой future ошибкой [CommandCanceled]. Сделанное до
/// отмены остаётся сделанным — половина скопированных файлов никуда не денется.
abstract interface class CancellableCommand implements Command {
  void cancel();
}

/// Команда, работу которой можно приостановить и продолжить.
abstract interface class SuspendableCommand implements Command {
  bool get suspended;

  void suspend();

  void resume();
}

/// Работа прервана — по просьбе пользователя или потому, что отменили того,
/// в чьём составе она шла.
///
/// Не ошибка: показывать её как сбой неверно, поэтому у неё свой тип, а
/// составные команды отличают отмену от падения.
class CommandCanceled implements Exception {
  const CommandCanceled([this.command]);

  /// Что именно отменили; null — отменили саму составную команду.
  final Command? command;

  @override
  String toString() => command == null ? 'Command canceled' : 'Command canceled: $command';
}

/// Команда не уложилась в отведённое время.
///
/// Ожидание прекращается всегда, а сама работа — только если её есть чем
/// прервать ([CancellableCommand]): иначе она доработает в стороне, но её
/// результата уже никто не ждёт.
class CommandTimeout implements Exception {
  const CommandTimeout(this.command, this.duration);

  final Command command;
  final Duration duration;

  @override
  String toString() => 'Command timed out after ${duration.inMilliseconds} ms: $command';
}

/// Ошибка внутри составной команды.
///
/// Оборачивает исходную причину, добавляя к ней то, чего в ней нет: какая
/// команда упала и в составе чего она шла. Аналог `CommandFailure` референса.
class CommandFailure implements Exception {
  const CommandFailure(this.executor, this.command, this.cause);

  /// Составная команда, внутри которой всё случилось.
  final Command executor;

  /// Команда, которая упала.
  final Command command;

  /// Что случилось на этом уровне. У вложенной составной команды это будет
  /// её собственный [CommandFailure] — так видно всю цепочку.
  final Object cause;

  /// Исходная причина, без обёрток.
  ///
  /// Составные команды вкладываются друг в друга, и падение шага на третьем
  /// уровне приходит наверх завёрнутым трижды. Цепочка нужна для журнала,
  /// а тому, кто разбирает ошибку, нужна причина — вот она.
  Object get rootCause {
    final inner = cause;
    return inner is CommandFailure ? inner.rootCause : inner;
  }

  @override
  String toString() => 'Command failed: $command in $executor ($cause)';
}

/// Чем закончилась одна команда.
///
/// Составная команда собирает такие итоги по всем своим шагам: по ним
/// строятся обработчики `allResults` и решается судьба группы.
class CommandResult {
  const CommandResult.completed(this.command, [this.value]) : error = null, canceled = false;

  const CommandResult.failed(this.command, this.error) : value = null, canceled = false;

  const CommandResult.canceled(this.command) : value = null, error = null, canceled = true;

  final Command command;

  /// Результат [ResultCommand]; null — команда ничего не передаёт дальше.
  final Object? value;

  /// Причина падения; null — команда не падала.
  final Object? error;

  /// Работу прервали.
  final bool canceled;

  /// Команда доработала до конца.
  bool get complete => error == null && !canceled;

  @override
  String toString() {
    if (canceled) {
      return 'canceled: $command';
    }
    return error == null ? 'completed: $command' : 'failed: $command ($error)';
  }
}
