import '../app_controller.dart';
import 'app_command.dart';
import 'key_combination.dart';

/// Установленные команды и разбор нажатий по ним.
///
/// Порядок установки задаёт приоритет, поэтому специализированные команды
/// («Enter на архиве») ставятся раньше общих («Enter»). Схема повторяет
/// `ApplicationImpl.processKeyboardCombination` из референса.
class CommandRegistry {
  CommandRegistry([List<AppCommand> commands = const []]) {
    _installed.addAll(commands);
  }

  final List<AppCommand> _installed = [];
  AppController? _app;

  Iterable<AppCommand> get installed => _installed;

  /// Связывает реестр с приложением и инициализирует команды.
  void attach(AppController app) {
    _app = app;
    _installed.removeWhere((command) => !command.init(app));
  }

  void install(AppCommand command) {
    final app = _app;
    if (app != null && !command.init(app)) {
      return;
    }
    _installed.add(command);
  }

  AppCommand? find(String id) {
    for (final command in _installed) {
      if (command.id == id) {
        return command;
      }
    }
    return null;
  }

  AppCommand? commandForSlot(FunctionKeySlot slot) {
    for (final command in _installed) {
      if (command.functionKey == slot) {
        return command;
      }
    }
    return null;
  }

  /// Находит подходящую команду и выполняет её.
  ///
  /// false — ничего не подошло; тогда событие клавиатуры уходит дальше по
  /// дереву Flutter.
  bool dispatch(KeyCombination combination) {
    final app = _app;
    if (app == null) {
      return false;
    }

    final node = app.activePanel.currentNode;
    for (final command in _installed) {
      for (final binding in command.bindings) {
        if (!binding.matches(combination, node)) {
          continue;
        }
        final context = contextFor(command);
        if (!command.isExecutable(context)) {
          continue;
        }
        command.execute(context);
        return true;
      }
    }
    return false;
  }

  /// Запуск команды не с клавиатуры — кнопкой нижней панели, из меню или из
  /// списка команд. Результат тот же, что и по горячей клавише.
  bool run(AppCommand command) {
    if (_app == null) {
      return false;
    }
    final context = contextFor(command);
    if (!command.isExecutable(context)) {
      return false;
    }
    command.execute(context);
    return true;
  }

  bool isExecutable(AppCommand command) {
    return _app != null && command.isExecutable(contextFor(command));
  }

  CommandContext contextFor(AppCommand command) {
    final app = _app!;
    final panel = app.activePanel;
    final node = panel.currentNode;
    final marked = panel.selection.nodes;

    return CommandContext(
      app: app,
      panel: panel,
      node: node,
      // Если пометки нет, операция работает с объектом под курсором.
      targets: marked.isNotEmpty ? marked : [if (node != null) node],
    );
  }

  Future<void> shutdown() async {
    for (final command in _installed) {
      await command.shutdown();
    }
  }
}
