import 'dart:async';

import 'package:fc_api/fc_api.dart';

/// Команда, которая только отмечается в журнале: по нему проверяется порядок.
class LoggingCommand implements Command {
  LoggingCommand(this.name, this.log, {this.delay = Duration.zero});

  final String name;
  final List<String> log;
  final Duration delay;

  @override
  Future<void> execute() async {
    log.add('$name:start');
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    log.add('$name:done');
  }

  @override
  String toString() => name;
}

/// Команда с результатом: его подхватывают следующие шаги.
class ValueCommand<T extends Object> implements ResultCommand<T> {
  ValueCommand(this.value);

  final T value;

  @override
  T? result;

  @override
  Future<void> execute() async => result = value;

  @override
  String toString() => 'ValueCommand($value)';
}

/// Команда, которая берёт из данных то, что положил предыдущий шаг.
class ConsumingCommand<T extends Object> implements Command {
  ConsumingCommand(this.data);

  final CommandData data;
  T? taken;

  @override
  Future<void> execute() async => taken = data.getObject<T>();
}

/// Команда, которая падает.
class FailingCommand implements Command {
  FailingCommand([this.error = 'сломалось']);

  final Object error;

  @override
  Future<void> execute() async => throw error;

  @override
  String toString() => 'FailingCommand';
}

/// Команда, которую можно прервать: работает, пока не отменят или не отпустят.
class BlockingCommand implements CancellableCommand {
  BlockingCommand([this.name = 'blocking']);

  final String name;
  final Completer<void> _completion = Completer<void>();

  bool started = false;
  bool canceled = false;

  @override
  Future<void> execute() {
    started = true;
    return _completion.future;
  }

  /// Отпускает команду штатно.
  void finish() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  @override
  void cancel() {
    canceled = true;
    if (!_completion.isCompleted) {
      _completion.completeError(CommandCanceled(this));
    }
  }

  @override
  String toString() => name;
}

/// Команда, которая отменяет себя сама.
class SelfCancelingCommand implements Command {
  @override
  Future<void> execute() async => throw const CommandCanceled();

  @override
  String toString() => 'SelfCancelingCommand';
}

/// Окружение, которое записывает, что и когда с командами происходило.
class RecordingLifecycle implements CommandLifecycle {
  RecordingLifecycle([this.log = const []]);

  final List<String> log;
  int created = 0;

  @override
  Command createInstance(CommandFactory factory, CommandData data) {
    created++;
    log.add('create');
    return factory(data);
  }

  @override
  void beforeExecution(Command command, CommandData data) => log.add('before:$command');

  @override
  void afterCompletion(Command command, CommandResult result) => log.add('after:$command:${result.complete}');
}
