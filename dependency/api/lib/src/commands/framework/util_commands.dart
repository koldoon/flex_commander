import 'dart:async';

import 'command.dart';

/// Обычная функция как команда.
///
/// Аналог `DelegateCommand` референса и его же «лёгких команд»: не всякая
/// работа заслуживает своего класса, а составлять её с остальными всё равно
/// нужно.
class DelegateCommand implements Command {
  DelegateCommand(this.body, {this.description});

  final Future<void> Function() body;
  final String? description;

  @override
  Future<void> execute() => body();

  @override
  String toString() => description ?? 'DelegateCommand';
}

/// Пауза. Нужна между шагами: дать системе доделать своё, развести две
/// операции во времени.
class DelayCommand implements CancellableCommand {
  DelayCommand(this.duration);

  final Duration duration;

  Timer? _timer;
  Completer<void>? _completion;

  @override
  Future<void> execute() {
    final completion = Completer<void>();
    _completion = completion;
    _timer = Timer(duration, () {
      _timer = null;
      if (!completion.isCompleted) {
        completion.complete();
      }
    });
    return completion.future;
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.completeError(CommandCanceled(this));
    }
  }

  @override
  String toString() => 'DelayCommand(${duration.inMilliseconds} ms)';
}
