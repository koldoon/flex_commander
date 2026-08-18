import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/application.dart';
import 'app_command.dart';
import 'command_service.dart';
import 'framework/framework.dart';
import 'key_combination.dart';

/// Куда уходит ошибка команды, у которой нет окна.
///
/// У команды с окном ошибка остаётся в нём — пользователь видит её и может
/// исправить ввод. У команды без окна показать её негде, а молчать нельзя:
/// приложение отдаёт сюда журнал, тесты — список.
typedef CommandErrorHandler = void Function(Object error, Command command);

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
class CommandRegistry extends ChangeNotifier implements CommandService, CommandLifecycle {
  CommandRegistry([List<AppCommandFactory> commands = const [], List<KeyBinding> bindings = const [], this.onError]) {
    _factories.addAll(commands);
    _bindings.addAll(bindings);
  }

  /// Куда сообщать об ошибке команды без окна; null — молча.
  final CommandErrorHandler? onError;

  final List<AppCommandFactory> _factories = [];

  /// Фабрика по идентификатору команды. Заполняется при установке: искать её
  /// перебором значило бы создавать все команды подряд на каждое нажатие.
  final Map<String, AppCommandFactory> _factoryById = {};
  final List<KeyBinding> _bindings = [];

  /// Экземпляр на команду для опроса: название, выполнимость. Своё окно он
  /// не открывает и состояния исполнения не хранит — для работы создаётся
  /// отдельный экземпляр.
  final Map<String, AppCommand> _prototypes = {};

  final List<AppCommand> _openDialogs = [];

  Application? _app;
  int _lastRunId = 0;

  /// Команды в порядке установки — то, что увидит список команд.
  @override
  List<AppCommand> get installed => List.unmodifiable(_prototypes.values);

  /// Все привязки в порядке приоритета.
  @override
  List<KeyBinding> get bindings => List.unmodifiable(_bindings);

  /// Запущенные команды, которым нужно окно. Ядро рисует их поверх приложения.
  @override
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
      _factoryById[command.id] = factory;
    }
  }

  /// Ставит команду. Набор команд меняется и после запуска — модуль может
  /// поставить свою, — поэтому об установке сообщается наружу: нижняя панель
  /// и список команд перерисовываются по уведомлению.
  @override
  void install(AppCommandFactory factory) {
    _factories.add(factory);
    final app = _app;
    if (app == null) {
      return;
    }
    final command = factory();
    if (command.init(app)) {
      _prototypes[command.id] = command;
      _factoryById[command.id] = factory;
      notifyListeners();
    }
  }

  /// Закрепляет комбинацию за командой. Более ранние привязки имеют приоритет.
  @override
  void bind(KeyBinding binding) {
    _bindings.add(binding);
    notifyListeners();
  }

  /// Снимает все привязки команды — например, при переназначении клавиш.
  @override
  void unbind(String commandId) {
    final before = _bindings.length;
    _bindings.removeWhere((binding) => binding.commandId == commandId);
    if (_bindings.length != before) {
      notifyListeners();
    }
  }

  /// Чем вызывается команда: для подсказок в списке команд и в настройках.
  @override
  List<KeyBinding> bindingsOf(String commandId) =>
      _bindings.where((binding) => binding.commandId == commandId).toList(growable: false);

  @override
  AppCommand? find(String id) => _prototypes[id];

  /// Команда, закреплённая за комбинацией клавиш прямо сейчас.
  ///
  /// Сначала ищется выполнимая — та, что действительно запустится по нажатию;
  /// если такой нет, возвращается первая подходящая, чтобы кнопка нижней панели
  /// всё равно показала название и осталась приглушённой.
  @override
  AppCommand? commandFor(KeyCombination combination) => _prototypes[bindingFor(combination)?.commandId];

  /// Привязка, которая сработает по этой комбинации прямо сейчас.
  ///
  /// Сначала ищется та, чья команда действительно выполнится; если такой нет,
  /// возвращается первая подходящая, чтобы кнопка нижней панели всё равно
  /// показала название и осталась приглушённой.
  @override
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
  @override
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
  @override
  bool run(String commandId, {Map<String, Object?> parameters = const {}}) {
    final app = _app;
    final prototype = _prototypes[commandId];
    if (app == null || prototype == null) {
      return false;
    }
    if (!prototype.isExecutable(contextFor(prototype))) {
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
      beforeExecution(command, CommandData());
      return true;
    }

    // Запуск не ждут: нажатие клавиши не может стоять и ждать конца работы.
    // Но исход разбирается — раньше ошибка команды без окна пропадала совсем.
    unawaited(_runToCompletion(command));
    return true;
  }

  /// Выполняет команду и разбирает исход: закрывает окно, если оно было, и
  /// сообщает об ошибке.
  Future<void> _runToCompletion(AppCommand command) async {
    final data = CommandData();
    beforeExecution(command, data);

    CommandResult result;
    try {
      await command.execute();
      result = CommandResult.completed(command);
    } on CommandCanceled {
      result = CommandResult.canceled(command);
    } catch (error) {
      result = CommandResult.failed(command, error);
    }

    afterCompletion(command, result);
  }

  /// Создаёт экземпляр команды и связывает его с запуском, но не выполняет.
  ///
  /// Так команду получают те, кто задаёт параметры сам: окно команды, меню,
  /// сценарий, будущая командная строка.
  @override
  AppCommand? create(String commandId) {
    final app = _app;
    final factory = _factoryById[commandId];
    if (app == null || factory == null) {
      return null;
    }

    final command = factory();
    command.attachRun(runId: '$commandId#${++_lastRunId}', context: contextFor(command));
    return command;
  }

  /// Закрывает окно запущенной команды. Вызывается самой командой по [runId].
  @override
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

  @override
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

  // --- Окружение командного фреймворка ---
  //
  // Реестр — это [CommandLifecycle] приложения: он создаёт действия, следит за
  // их окнами и разбирает исход. Поэтому команда, запущенная клавишей, и она
  // же в составе последовательности проходят один и тот же путь.

  @override
  Command createInstance(CommandFactory factory, CommandData data) {
    final command = factory(data);
    if (command is AppCommand) {
      _attachRun(command);
    }
    return command;
  }

  /// Учёт окна: команда с окном попадает в список открытых, и ядро его рисует.
  ///
  /// Команда с окном внутри составной команды — случай, до которого дело ещё
  /// не дошло: окно соберёт параметры само, а составная команда в это время
  /// будет ждать её завершения. Разбирается это вместе с фоновыми работами.
  @override
  void beforeExecution(Command command, CommandData data) {
    if (command is! AppCommand) {
      return;
    }
    _attachRun(command);

    if (command.hasDialog && !command.hasOpenDialog) {
      command.setDialogOpen(true);
      _openDialogs.add(command);
      notifyListeners();
    }
  }

  @override
  void afterCompletion(Command command, CommandResult result) {
    if (command is AppCommand) {
      closeDialog(command.runId);
    }

    final error = result.error;
    if (error != null) {
      onError?.call(error, command);
    }
  }

  /// Связывает команду с запуском, если этого ещё не сделали: во фреймворк
  /// команда может прийти и готовой, созданной вручную.
  void _attachRun(AppCommand command) {
    if (command.runId.isNotEmpty) {
      return;
    }
    command.attachRun(runId: '${command.id}#${++_lastRunId}', context: contextFor(command));
  }
}
