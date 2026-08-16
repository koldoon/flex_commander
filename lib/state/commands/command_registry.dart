import 'package:flutter/foundation.dart';

import '../../model/app/application.dart';
import 'app_command.dart';
import 'key_combination.dart';

/// Команды приложения, привязки клавиш к ним и открытые окна команд.
///
/// Реестр — единственное место, где живут привязки: он их устанавливает,
/// хранит, отдаёт наружу и разбирает по ним нажатия. Команды о клавишах ничего
/// не знают, поэтому переназначение горячих клавиш (позже — из настроек)
/// не затрагивает ни одну команду.
///
/// Он же создаёт команды: **на каждый запуск — свой экземпляр**, потому что
/// команда хранит состояние исполнения. Экземпляр получает идентификатор
/// запуска, и если у команды есть окно, реестр держит её в списке открытых,
/// пока команда сама не попросит закрыть.
///
/// Привязка может нести и значения для команды ([KeyBinding.parameters]): одна
/// команда с разными значениями на разных клавишах — приём референса.
///
/// Порядок привязок задаёт приоритет: специализированные ставятся раньше общих,
/// поэтому `Esc` во время чтения каталога отменяет операцию, а в остальное
/// время снимает пометку. Схема повторяет
/// `ApplicationImpl.processKeyboardCombination` из референса.
class CommandRegistry extends ChangeNotifier {
  CommandRegistry([List<CommandFactory> commands = const [], List<KeyBinding> bindings = const []]) {
    _factories.addAll(commands);
    _bindings.addAll(bindings);
  }

  final List<CommandFactory> _factories = [];
  final List<KeyBinding> _bindings = [];

  /// Экземпляр на команду для опроса: название, выполнимость. Своё окно он
  /// не открывает и состояния исполнения не хранит — для работы создаётся
  /// отдельный экземпляр.
  final Map<String, AppCommand> _prototypes = {};

  final List<AppCommand> _openDialogs = [];

  Application? _app;
  int _lastRunId = 0;

  /// Команды в порядке установки — то, что увидит список команд.
  List<AppCommand> get installed => List.unmodifiable(_prototypes.values);

  /// Все привязки в порядке приоритета.
  List<KeyBinding> get bindings => List.unmodifiable(_bindings);

  /// Запущенные команды, которым нужно окно. Ядро рисует их поверх приложения.
  List<AppCommand> get openDialogs => List.unmodifiable(_openDialogs);

  /// Связывает реестр с приложением и создаёт прототипы команд.
  void attach(Application app) {
    _app = app;
    for (final factory in _factories) {
      final command = factory();
      if (!command.init(app)) {
        continue;
      }
      _prototypes[command.id] = command;
    }
  }

  void install(CommandFactory factory) {
    _factories.add(factory);
    final app = _app;
    if (app == null) {
      return;
    }
    final command = factory();
    if (command.init(app)) {
      _prototypes[command.id] = command;
    }
  }

  /// Закрепляет комбинацию за командой. Более ранние привязки имеют приоритет.
  void bind(KeyBinding binding) => _bindings.add(binding);

  /// Снимает все привязки команды — например, при переназначении клавиш.
  void unbind(String commandId) => _bindings.removeWhere((binding) => binding.commandId == commandId);

  /// Чем вызывается команда: для подсказок в списке команд и в настройках.
  List<KeyBinding> bindingsOf(String commandId) =>
      _bindings.where((binding) => binding.commandId == commandId).toList(growable: false);

  AppCommand? find(String id) => _prototypes[id];

  /// Команда, закреплённая за комбинацией клавиш прямо сейчас.
  ///
  /// Сначала ищется выполнимая — та, что действительно запустится по нажатию;
  /// если такой нет, возвращается первая подходящая, чтобы кнопка нижней панели
  /// всё равно показала название и осталась приглушённой.
  AppCommand? commandFor(KeyCombination combination) => _prototypes[bindingFor(combination)?.commandId];

  /// Привязка, которая сработает по этой комбинации прямо сейчас.
  ///
  /// Сначала ищется та, чья команда действительно выполнится; если такой нет,
  /// возвращается первая подходящая, чтобы кнопка нижней панели всё равно
  /// показала название и осталась приглушённой.
  KeyBinding? bindingFor(KeyCombination combination) {
    final app = _app;
    if (app == null) {
      return null;
    }

    final node = app.activePanel.currentNode;
    KeyBinding? fallback;

    for (final binding in _bindings) {
      if (!binding.matches(combination, node)) {
        continue;
      }
      final command = _prototypes[binding.commandId];
      if (command == null) {
        // Привязка к неизвестной команде: могла остаться от старых настроек.
        continue;
      }
      if (command.isExecutable(contextFor(command))) {
        return binding;
      }
      fallback ??= binding;
    }
    return fallback;
  }

  /// Находит подходящую команду и выполняет её.
  ///
  /// false — ничего не подошло; тогда событие клавиатуры уходит дальше по
  /// дереву Flutter.
  bool dispatch(KeyCombination combination) {
    final binding = bindingFor(combination);
    if (binding == null) {
      return false;
    }
    // Кнопка нижней панели дёргает тот же dispatch, поэтому нажатие мышью и
    // нажатие клавиши не могут разойтись.
    return run(binding.commandId, parameters: binding.parametersFor(combination));
  }

  /// Запускает команду по идентификатору — с клавиатуры, кнопкой, из меню или
  /// из списка команд. Результат всюду одинаковый.
  ///
  /// Для работы создаётся новый экземпляр: состояние исполнения принадлежит
  /// запуску, а не команде вообще.
  bool run(String commandId, {Map<String, Object?> parameters = const {}}) {
    final app = _app;
    final prototype = _prototypes[commandId];
    if (app == null || prototype == null) {
      return false;
    }
    if (!prototype.isExecutable(contextFor(prototype))) {
      return false;
    }

    final factory = _factoryFor(commandId);
    if (factory == null) {
      return false;
    }

    final command = create(commandId);
    if (command == null || !command.isExecutable(command.context)) {
      return false;
    }
    // Значения проставляются до запуска: окно команды может их изменить, а
    // если окна нет, команда выполнится ровно с ними.
    parameters.forEach(command.setParam);

    if (command.hasDialog) {
      // У команды есть окно: оно соберёт параметры и вызовет execute само.
      command.setDialogOpen(true);
      _openDialogs.add(command);
      notifyListeners();
      return true;
    }

    command.execute();
    return true;
  }

  /// Создаёт экземпляр команды и связывает его с запуском, но не выполняет.
  ///
  /// Так команду получают те, кто задаёт параметры сам: окно команды, меню,
  /// сценарий, будущая командная строка.
  AppCommand? create(String commandId) {
    final app = _app;
    final factory = _factoryFor(commandId);
    if (app == null || factory == null) {
      return null;
    }

    final command = factory();
    command.attachRun(runId: '$commandId#${++_lastRunId}', context: contextFor(command));
    return command;
  }

  /// Закрывает окно запущенной команды. Вызывается самой командой по [runId].
  void closeDialog(String runId) {
    final before = _openDialogs.length;
    for (final command in _openDialogs.where((command) => command.runId == runId)) {
      command.setDialogOpen(false);
    }
    _openDialogs.removeWhere((command) => command.runId == runId);
    if (_openDialogs.length != before) {
      notifyListeners();
    }
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
    for (final command in _prototypes.values) {
      await command.shutdown();
    }
  }

  CommandFactory? _factoryFor(String commandId) {
    for (final factory in _factories) {
      // Прототипы уже созданы, поэтому здесь достаточно сверить идентификатор
      // у свежего экземпляра — команды дешёвые.
      final command = factory();
      if (command.id == commandId) {
        return factory;
      }
    }
    return null;
  }
}
