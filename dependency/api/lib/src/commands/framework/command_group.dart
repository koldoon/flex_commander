import 'command.dart';
import 'command_executor.dart';

/// Несколько команд как одна.
///
/// Аналог `CommandGroup` референса. Разновидностей две: одна за другой
/// ([CommandSequence]) и все разом ([ParallelCommands]).
abstract class CommandGroup extends CommandExecutorBase {
  CommandGroup({super.description, super.skipErrors, super.skipCancellations});

  final List<Command> _commands = [];

  /// Команды в порядке добавления.
  List<Command> get commands => List.unmodifiable(_commands);

  void addCommand(Command command) => _commands.add(command);
}

/// Команды одна за другой.
///
/// Следующая начинается, когда предыдущая закончила, и видит её результат
/// в общих данных. Ошибка или отмена шага останавливает всю
/// последовательность — если только группе не велено их пропускать.
class CommandSequence extends CommandGroup {
  CommandSequence({super.description, super.skipErrors, super.skipCancellations});

  @override
  Future<void> execute() async {
    for (final command in commands) {
      // Пауза и отмена разбираются между шагами: остановить уже запущенный
      // шаг может только он сам.
      await awaitResume();
      if (canceled) {
        throw const CommandCanceled();
      }
      acceptResult(await runChild(command));
    }
  }
}

/// Все команды разом.
///
/// Группа заканчивается, когда закончили все: даже если первая же упала,
/// остальные доводятся до конца — прерывать их на полпути значило бы оставлять
/// работу недоделанной без всякой на то причины. Судьба группы решается по
/// собранным итогам: первая ошибка роняет её, первая отмена — отменяет.
class ParallelCommands extends CommandGroup {
  ParallelCommands({super.description, super.skipErrors, super.skipCancellations});

  @override
  Future<void> execute() async {
    if (canceled) {
      throw const CommandCanceled();
    }

    // runChild не бросает: итог каждого шага возвращается значением, поэтому
    // ожидание не оборвётся на первом же падении.
    final results = await Future.wait(commands.map(runChild));
    for (final result in results) {
      acceptResult(result);
    }
  }
}
