import 'command.dart';
import 'command_data.dart';
import 'command_executor.dart';
import 'command_group.dart';
import 'command_lifecycle.dart';
import 'command_proxy.dart';
import 'util_commands.dart';

/// С чего начинается любая составная команда.
///
/// Точка входа фреймворка — как `Commands` в референсе:
///
/// ```dart
/// await Commands.asSequence()
///     .add(ExtractArchiveCommand())
///     .create(CopyCommand.new)
///     .data(destination)
///     .timeout(const Duration(minutes: 5))
///     .error((failure) => logger.error('Copy failed', failure))
///     .execute();
/// ```
abstract final class Commands {
  /// Готовая команда с обвязкой: сроком и обработчиками.
  static CommandProxyBuilder wrap(Command command) => CommandProxyBuilder(target: command);

  /// Команда, которую создадут при запуске — фабрикой или контейнером
  /// ([CommandLifecycle.createInstance]). Так шаг получает то, что станет
  /// известно только по ходу работы предыдущих.
  static CommandProxyBuilder create(CommandFactory factory) => CommandProxyBuilder(factory: factory);

  /// Обычная функция как шаг.
  static CommandProxyBuilder of(Future<void> Function() body, {String? description}) =>
      CommandProxyBuilder(target: DelegateCommand(body, description: description));

  /// Пауза как шаг.
  static CommandProxyBuilder delay(Duration duration) => CommandProxyBuilder(target: DelayCommand(duration));

  /// Команды одна за другой.
  static CommandGroupBuilder asSequence() => CommandGroupBuilder(sequence: true);

  /// Команды разом.
  static CommandGroupBuilder inParallel() => CommandGroupBuilder(sequence: false);
}

/// Общее у построителей: данные, окружение и запуск.
abstract class CommandBuilderBase {
  final List<Object> _data = [];
  CommandLifecycle? _lifecycle;

  /// Собирает составную команду, но не запускает: её можно вложить в другую
  /// или сохранить на потом.
  CommandExecutor build();

  /// Собирает и выполняет.
  Future<void> execute() => build().execute();

  void _applyTo(CommandExecutorBase executor) {
    for (final value in _data) {
      executor.addData(value);
    }
    final lifecycle = _lifecycle;
    if (lifecycle != null) {
      executor.useLifecycle(lifecycle);
    }
  }
}

/// Построитель обёртки над одной командой.
class CommandProxyBuilder extends CommandBuilderBase {
  CommandProxyBuilder({Command? target, CommandFactory? factory}) : _target = target, _factory = factory;

  final Command? _target;
  final CommandFactory? _factory;

  String? _description;
  Duration? _timeout;
  void Function(Object? value)? _onResult;
  void Function(Object error)? _onError;
  void Function()? _onCancel;

  CommandProxyBuilder description(String value) {
    _description = value;
    return this;
  }

  /// Сколько ждать. По истечении срока ожидание прекращается, а работа
  /// останавливается, если её есть чем остановить.
  CommandProxyBuilder timeout(Duration value) {
    _timeout = value;
    return this;
  }

  /// Кладёт значение в данные команды.
  CommandProxyBuilder data(Object value) {
    _data.add(value);
    return this;
  }

  /// Кто создаёт команду и что происходит до и после неё.
  CommandProxyBuilder lifecycle(CommandLifecycle value) {
    _lifecycle = value;
    return this;
  }

  CommandProxyBuilder result(void Function(Object? value) handler) {
    _onResult = handler;
    return this;
  }

  /// Обработчик ошибки. Поставили — значит, взяли ответственность: наружу
  /// ошибка больше не уходит.
  CommandProxyBuilder error(void Function(Object error) handler) {
    _onError = handler;
    return this;
  }

  /// Обработчик отмены — с той же оговоркой, что и у [error].
  CommandProxyBuilder cancel(void Function() handler) {
    _onCancel = handler;
    return this;
  }

  @override
  CommandExecutor build() {
    final proxy =
        CommandProxy(target: _target, factory: _factory, timeout: _timeout, description: _description)
          ..onResult = _onResult
          ..onError = _onError
          ..onCancel = _onCancel;
    _applyTo(proxy);
    return proxy;
  }
}

/// Построитель группы: последовательности или параллели.
class CommandGroupBuilder extends CommandBuilderBase {
  CommandGroupBuilder({required bool sequence}) : _sequence = sequence;

  final bool _sequence;
  final List<Command> _commands = [];

  String? _description;
  bool _skipErrors = false;
  bool _skipCancellations = false;
  void Function(Object? value)? _onLastResult;
  void Function(List<CommandResult> results)? _onAllResults;
  void Function(Object error)? _onError;
  void Function()? _onCancel;

  CommandGroupBuilder add(Command command) {
    _commands.add(command);
    return this;
  }

  /// Шаг, который создадут при запуске.
  CommandGroupBuilder create(CommandFactory factory) {
    _commands.add(CommandProxy(factory: factory));
    return this;
  }

  CommandGroupBuilder description(String value) {
    _description = value;
    return this;
  }

  CommandGroupBuilder data(Object value) {
    _data.add(value);
    return this;
  }

  CommandGroupBuilder lifecycle(CommandLifecycle value) {
    _lifecycle = value;
    return this;
  }

  /// Результат последнего выполненного шага.
  CommandGroupBuilder lastResult(void Function(Object? value) handler) {
    _onLastResult = handler;
    return this;
  }

  /// Итоги всех шагов — включая пропущенные ошибки и отмены.
  CommandGroupBuilder allResults(void Function(List<CommandResult> results) handler) {
    _onAllResults = handler;
    return this;
  }

  /// Обработчик ошибки: поставили — ошибка наружу не уходит.
  CommandGroupBuilder error(void Function(Object error) handler) {
    _onError = handler;
    return this;
  }

  /// Обработчик отмены — с той же оговоркой, что и у [error].
  CommandGroupBuilder cancel(void Function() handler) {
    _onCancel = handler;
    return this;
  }

  /// Ошибка шага не роняет всю группу: итог такого шага попадёт в [allResults].
  CommandGroupBuilder skipErrors({bool value = true}) {
    _skipErrors = value;
    return this;
  }

  /// Отмена шага не отменяет всю группу.
  CommandGroupBuilder skipCancellations({bool value = true}) {
    _skipCancellations = value;
    return this;
  }

  @override
  CommandExecutor build() {
    final group =
        _sequence
            ? CommandSequence(description: _description, skipErrors: _skipErrors, skipCancellations: _skipCancellations)
            : ParallelCommands(
              description: _description,
              skipErrors: _skipErrors,
              skipCancellations: _skipCancellations,
            );

    for (final command in _commands) {
      group.addCommand(command);
    }
    _applyTo(group);

    return _GroupWithHandlers(
      group,
      onLastResult: _onLastResult,
      onAllResults: _onAllResults,
      onError: _onError,
      onCancel: _onCancel,
    );
  }
}

/// Группа с обработчиками итога.
///
/// Отдельная обёртка, а не поля группы: сама группа занята порядком шагов, и
/// добавлять ей знание о том, кто и как разбирает итог, незачем.
class _GroupWithHandlers implements CommandExecutor {
  _GroupWithHandlers(this._group, {this.onLastResult, this.onAllResults, this.onError, this.onCancel});

  final CommandGroup _group;
  final void Function(Object? value)? onLastResult;
  final void Function(List<CommandResult> results)? onAllResults;
  final void Function(Object error)? onError;
  final void Function()? onCancel;

  @override
  Future<void> execute() async {
    try {
      await _group.execute();
    } on CommandCanceled {
      _report();
      final handler = onCancel;
      if (handler == null) {
        rethrow;
      }
      handler();
      return;
    } catch (error) {
      _report();
      final handler = onError;
      if (handler == null) {
        rethrow;
      }
      handler(error);
      return;
    }
    _report();
  }

  void _report() {
    onAllResults?.call(_group.results);
    if (_group.results.isNotEmpty) {
      onLastResult?.call(_group.results.last.value);
    }
  }

  /// Данные группы — её результат: так сделанное внутри доходит наружу.
  @override
  CommandData? get result => _group.result;

  @override
  bool get cancellable => _group.cancellable;

  @override
  bool get suspendable => _group.suspendable;

  @override
  bool get suspended => _group.suspended;

  @override
  List<CommandResult> get results => _group.results;

  @override
  void prepare(CommandLifecycle lifecycle, CommandData data) => _group.prepare(lifecycle, data);

  @override
  void cancel() => _group.cancel();

  @override
  void suspend() => _group.suspend();

  @override
  void resume() => _group.resume();

  @override
  String toString() => _group.toString();
}
