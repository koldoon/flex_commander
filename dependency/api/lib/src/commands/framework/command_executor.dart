import 'dart:async';

import 'package:flutter/foundation.dart';

import 'command.dart';
import 'command_data.dart';
import 'command_lifecycle.dart';

/// Команда, которая исполняет другие команды: обёртка или группа.
///
/// Наружу она выглядит обычной командой — этим и держится вложенность:
/// последовательность внутри параллели внутри обёртки собирается без
/// единого особого случая.
abstract interface class CommandExecutor implements CancellableCommand, SuspendableCommand, ResultCommand<CommandData> {
  /// Есть ли чем прервать всё, что сейчас работает.
  bool get cancellable;

  /// Есть ли чем приостановить всё, что сейчас работает.
  bool get suspendable;

  /// Передаёт составной команде окружение: как создавать команды и что уже
  /// известно. Вызывает тот, кто её исполняет, — родительская составная
  /// команда или запускающий код.
  void prepare(CommandLifecycle lifecycle, CommandData data);

  /// Итоги выполненных шагов в порядке выполнения.
  List<CommandResult> get results;
}

/// Общая часть обёртки и групп: данные, окружение, запуск шага, приостановка
/// и отмена.
///
/// Здесь собрано то, что у всех составных команд одинаково, — как в референсе
/// (`AbstractCommandExecutor`). Наследнику остаётся решить, в каком порядке
/// запускать шаги и что делать с их итогами.
abstract class CommandExecutorBase implements CommandExecutor {
  CommandExecutorBase({this.description, bool skipErrors = false, bool skipCancellations = false})
    : _skipErrors = skipErrors,
      _skipCancellations = skipCancellations;

  /// Пояснение для журнала и отладки: «Открыть архив и скопировать».
  final String? description;

  /// Ошибка шага не роняет всю работу.
  final bool _skipErrors;

  /// Отмена шага не отменяет всю работу.
  final bool _skipCancellations;

  CommandLifecycle _lifecycle = const DefaultCommandLifecycle();
  CommandData? _data;

  /// Значения, добавленные до [prepare]: своих данных ещё нет, а терять их
  /// нельзя.
  final List<Object> _pending = [];

  final List<Command> _active = [];
  final List<CommandResult> _results = [];

  bool _canceled = false;
  bool _suspended = false;
  Completer<void>? _resumed;

  @override
  void prepare(CommandLifecycle lifecycle, CommandData data) {
    _lifecycle = lifecycle;
    _data = CommandData(parent: data)..addAll(_pending);
    _pending.clear();
  }

  /// Данные этого уровня. Если [prepare] не звали — своя область без родителя:
  /// команду запустили саму по себе, а не в составе другой.
  @protected
  CommandData get data {
    final existing = _data;
    if (existing != null) {
      return existing;
    }
    final created = CommandData()..addAll(_pending);
    _pending.clear();
    _data = created;
    return created;
  }

  @protected
  CommandLifecycle get lifecycle => _lifecycle;

  /// Кладёт значение в данные: так составной команде задают вход.
  void addData(Object value) {
    final existing = _data;
    if (existing == null) {
      _pending.add(value);
    } else {
      existing.add(value);
    }
  }

  void useLifecycle(CommandLifecycle lifecycle) => _lifecycle = lifecycle;

  @override
  List<CommandResult> get results => List.unmodifiable(_results);

  /// Данные составной команды целиком — они и есть её результат.
  ///
  /// Так сделанное внутри доходит наружу: обёртка отдаёт данные своего шага
  /// группе, группа — тому, кто её выполняет. Разворачивать вложенные данные
  /// умеет [CommandData.getObject], поэтому следующий шаг просто просит нужный
  /// ему тип и не знает, на какой глубине он появился.
  @override
  CommandData? get result => _data;

  @override
  bool get cancellable => _active.every((command) => command is CancellableCommand);

  @override
  bool get suspendable => _active.every((command) => command is SuspendableCommand);

  @override
  bool get suspended => _suspended;

  /// Работу составной команды прервали.
  @protected
  bool get canceled => _canceled;

  /// Выполняет один шаг и возвращает его итог.
  ///
  /// Итог возвращается, а не бросается: решать, ошибка это или повод
  /// продолжить, — дело наследника. Здесь же результат шага попадает в общие
  /// данные, а окружение узнаёт о начале и конце работы.
  @protected
  Future<CommandResult> runChild(Command command) async {
    _active.add(command);
    if (command is CommandExecutor) {
      command.prepare(_lifecycle, data);
    }

    CommandResult result;
    try {
      _lifecycle.beforeExecution(command, data);
      await command.execute();
      result = CommandResult.completed(command, command is ResultCommand ? command.result : null);
    } on CommandCanceled {
      result = CommandResult.canceled(command);
    } catch (error) {
      result = CommandResult.failed(command, error);
    } finally {
      _active.remove(command);
    }

    _lifecycle.afterCompletion(command, result);

    final value = result.value;
    if (value != null) {
      data.add(value);
    }
    _results.add(result);
    return result;
  }

  /// Ждёт снятия паузы. Наследник зовёт это между шагами: остановиться посреди
  /// уже запущенного шага нельзя, а между шагами — можно всегда.
  @protected
  Future<void> awaitResume() => _resumed?.future ?? Future<void>.value();

  /// Прерывает всё, что работает сейчас.
  @protected
  void cancelActive() {
    for (final command in _active.toList()) {
      if (command is CancellableCommand) {
        command.cancel();
      }
    }
  }

  /// Что делать с итогом шага: продолжать ли работу.
  ///
  /// Возвращает `true`, если можно идти дальше. Иначе бросает — отмену или
  /// [CommandFailure] с исходной причиной внутри.
  @protected
  bool acceptResult(CommandResult result) {
    if (result.canceled) {
      if (_skipCancellations) {
        return true;
      }
      _canceled = true;
      cancelActive();
      throw CommandCanceled(result.command);
    }

    final error = result.error;
    if (error != null) {
      if (_skipErrors) {
        return true;
      }
      cancelActive();
      throw CommandFailure(this, result.command, error);
    }
    return true;
  }

  /// Прерывает работу.
  ///
  /// В отличие от референса, прерывание не запрещено и тогда, когда прервать
  /// можно не всё: шаги, которым нечем остановиться, доработают до конца, но
  /// следующие уже не запустятся. Иначе отмена зависела бы от того, какой шаг
  /// идёт в этот момент, — для пользователя это выглядело бы случайностью.
  @override
  void cancel() {
    if (_canceled) {
      return;
    }
    _canceled = true;
    cancelActive();
    // Снять паузу, иначе отмена не дойдёт до остановленной между шагами работы.
    _resumed?.complete();
    _resumed = null;
    _suspended = false;
  }

  @override
  void suspend() {
    if (_suspended) {
      return;
    }
    _suspended = true;
    _resumed = Completer<void>();
    for (final command in _active) {
      if (command is SuspendableCommand && !command.suspended) {
        command.suspend();
      }
    }
  }

  @override
  void resume() {
    if (!_suspended) {
      return;
    }
    _suspended = false;
    for (final command in _active) {
      if (command is SuspendableCommand && command.suspended) {
        command.resume();
      }
    }
    _resumed?.complete();
    _resumed = null;
  }

  @override
  String toString() => description ?? runtimeType.toString();
}
