import 'dart:async';

import 'command.dart';
import 'command_executor.dart';
import 'command_lifecycle.dart';

/// Одна команда с обвязкой: срок, обработчики результата, ошибки и отмены.
///
/// Аналог `CommandProxy` референса. Нужен там, где команду надо выполнить не
/// «как есть»: ограничить временем, создать через контейнер, узнать об итоге
/// не исключением, а вызовом.
///
/// Обработчик — это ещё и решение, кто отвечает за исход: если ошибку взялись
/// обрабатывать здесь, наружу она не уходит и составная команда, в которой
/// этот шаг стоит, продолжает работу. Не хотите брать ответственность — не
/// ставьте обработчик, и ошибка пойдёт дальше.
class CommandProxy extends CommandExecutorBase {
  CommandProxy({Command? target, CommandFactory? factory, this.timeout, super.description})
    : _target = target,
      _factory = factory,
      assert(target != null || factory != null, 'Прокси нужна команда или её фабрика');

  final Command? _target;
  final CommandFactory? _factory;

  /// Сколько ждать; null — сколько угодно.
  final Duration? timeout;

  void Function(Object? value)? onResult;
  void Function(Object error)? onError;
  void Function()? onCancel;

  /// Команда, которую прокси исполняет. До запуска её может ещё не быть:
  /// созданием занимается окружение ([CommandLifecycle.createInstance]).
  Command? get target => _target;

  @override
  Future<void> execute() async {
    if (canceled) {
      throw const CommandCanceled();
    }

    final command = _target ?? lifecycle.createInstance(_factory!, data);
    final run = runChild(command);
    final limit = timeout;

    final result =
        limit == null
            ? await run
            : await run.timeout(
              limit,
              onTimeout: () {
                // Ждать перестаём в любом случае; саму работу останавливаем,
                // только если её есть чем остановить.
                if (command is CancellableCommand) {
                  command.cancel();
                }
                return CommandResult.failed(command, CommandTimeout(command, limit));
              },
            );

    if (result.canceled) {
      final handler = onCancel;
      if (handler == null) {
        throw CommandCanceled(command);
      }
      handler();
      return;
    }

    final error = result.error;
    if (error != null) {
      final handler = onError;
      if (handler == null) {
        throw CommandFailure(this, command, error);
      }
      handler(error);
      return;
    }

    onResult?.call(result.value);
  }
}
