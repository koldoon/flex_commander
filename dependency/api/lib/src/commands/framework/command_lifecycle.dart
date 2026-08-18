import 'command.dart';
import 'command_data.dart';

/// Как создать команду. Данные составной команды приходят параметром: из них
/// фабрика берёт то, что нужно её команде.
typedef CommandFactory = Command Function(CommandData data);

/// Создание команд и точки до и после их выполнения.
///
/// Через него в командный фреймворк входит всё, что фреймворка не касается:
/// контейнер зависимостей создаёт команду по-своему, приложение открывает и
/// закрывает её окно, журнал записывает начало и конец работы. Сам фреймворк
/// об этом не знает — он только зовёт эти три метода в нужные моменты.
///
/// Аналог `CommandLifecycle` референса; в приложении его реализует реестр
/// команд.
abstract interface class CommandLifecycle {
  /// Создаёт команду для запуска.
  Command createInstance(CommandFactory factory, CommandData data);

  /// Перед выполнением: здесь команде дают то, что ей нужно снаружи.
  void beforeExecution(Command command, CommandData data);

  /// После выполнения — при любом исходе, включая ошибку и отмену.
  void afterCompletion(Command command, CommandResult result);
}

/// Поведение по умолчанию: команда создаётся фабрикой, а до и после ничего
/// не происходит.
class DefaultCommandLifecycle implements CommandLifecycle {
  const DefaultCommandLifecycle();

  @override
  Command createInstance(CommandFactory factory, CommandData data) => factory(data);

  @override
  void beforeExecution(Command command, CommandData data) {}

  @override
  void afterCompletion(Command command, CommandResult result) {}
}
