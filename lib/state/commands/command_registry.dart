import '../../model/app/application.dart';
import 'app_command.dart';
import 'key_combination.dart';

/// Команды приложения и привязки клавиш к ним.
///
/// Реестр — единственное место, где живут привязки: он их устанавливает,
/// хранит, отдаёт наружу и разбирает по ним нажатия. Команды о клавишах ничего
/// не знают, поэтому переназначение горячих клавиш (позже — из настроек)
/// не затрагивает ни одну команду.
///
/// Порядок привязок задаёт приоритет: специализированные ставятся раньше общих,
/// поэтому `Esc` во время чтения каталога отменяет операцию, а в остальное
/// время снимает пометку. Схема повторяет
/// `ApplicationImpl.processKeyboardCombination` из референса.
class CommandRegistry {
  CommandRegistry([List<AppCommand> commands = const [], List<KeyBinding> bindings = const []]) {
    _installed.addAll(commands);
    _bindings.addAll(bindings);
  }

  final List<AppCommand> _installed = [];
  final List<KeyBinding> _bindings = [];
  Application? _app;

  Iterable<AppCommand> get installed => _installed;

  /// Все привязки в порядке приоритета.
  List<KeyBinding> get bindings => List.unmodifiable(_bindings);

  /// Связывает реестр с приложением и инициализирует команды.
  void attach(Application app) {
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

  /// Закрепляет комбинацию за командой. Более ранние привязки имеют приоритет.
  void bind(KeyBinding binding) => _bindings.add(binding);

  /// Снимает все привязки команды — например, при переназначении клавиш.
  void unbind(String commandId) => _bindings.removeWhere((binding) => binding.commandId == commandId);

  /// Чем вызывается команда: для подсказок в списке команд и в настройках.
  List<KeyBinding> bindingsOf(String commandId) =>
      _bindings.where((binding) => binding.commandId == commandId).toList(growable: false);

  AppCommand? find(String id) {
    for (final command in _installed) {
      if (command.id == id) {
        return command;
      }
    }
    return null;
  }

  /// Команда, закреплённая за комбинацией клавиш прямо сейчас.
  ///
  /// Сначала ищется выполнимая — та, что действительно запустится по нажатию;
  /// если такой нет, возвращается первая подходящая, чтобы кнопка нижней панели
  /// всё равно показала название и осталась приглушённой.
  AppCommand? commandFor(KeyCombination combination) {
    final app = _app;
    if (app == null) {
      return null;
    }

    final node = app.activePanel.currentNode;
    AppCommand? fallback;

    for (final binding in _bindings) {
      if (!binding.matches(combination, node)) {
        continue;
      }
      final command = find(binding.commandId);
      if (command == null) {
        // Привязка к неизвестной команде: могла остаться от старых настроек.
        continue;
      }
      if (command.isExecutable(contextFor(command))) {
        return command;
      }
      fallback ??= command;
    }
    return fallback;
  }

  /// Находит подходящую команду и выполняет её.
  ///
  /// false — ничего не подошло; тогда событие клавиатуры уходит дальше по
  /// дереву Flutter.
  bool dispatch(KeyCombination combination) {
    final command = commandFor(combination);
    if (command == null) {
      return false;
    }
    // Кнопка нижней панели дёргает тот же dispatch, поэтому нажатие мышью и
    // нажатие клавиши не могут разойтись.
    return run(command);
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
