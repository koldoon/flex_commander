import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/application.dart';
import '../app/viewport.dart';
import '../background/operations.dart';
import 'app_command.dart';
import 'command_service.dart';
import 'key_combination.dart';

/// Куда уходит ошибка команды, у которой нет окна.
///
/// У команды с окном ошибка остаётся в нём — пользователь видит её и может
/// исправить ввод. У команды без окна показать её негде, а молчать нельзя:
/// приложение отдаёт сюда журнал, тесты — список.
typedef CommandErrorHandler = void Function(Object error, AppCommand command);

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
class CommandRegistry extends ChangeNotifier implements CommandService, Operations {
  CommandRegistry([
    List<AppCommandFactory> commands = const [],
    List<KeyBinding> bindings = const [],
    this.onError,
    List<String> owners = const [],
  ]) {
    _factories.addAll(commands);
    _bindings.addAll(bindings);
    _owners.addAll(owners);
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

  /// Названия модулей — по тому же месту, что и фабрики; после [attach] то же
  /// самое лежит в [_ownerOf] уже по идентификатору команды.
  final List<String> _owners = [];
  final Map<String, String> _ownerOf = {};

  /// Кто принёс эту команду; пустая строка — принесли не модулем (тест,
  /// сценарий) или установили уже на ходу.
  ///
  /// Нужно справке: она показывает команды по модулям, и это единственное
  /// место, где такая связь есть.
  String ownerOf(String commandId) => _ownerOf[commandId] ?? '';

  /// Модули в порядке **объявления**, без повторов.
  ///
  /// Не в порядке [installed]: там команды лежат по первому появлению ключа, а
  /// модуль, занявший место чужой заглушки (просмотрщик встаёт на `F3`
  /// оболочки), остаётся на её месте — и порядок перестаёт быть похожим на
  /// список модулей. Здесь же порядок тот самый, которым задан и приоритет
  /// привязок.
  List<String> get owners {
    final seen = <String>[];
    for (final owner in _owners) {
      if (owner.isNotEmpty && !seen.contains(owner)) {
        seen.add(owner);
      }
    }
    return seen;
  }

  /// Запуски, ушедшие в фон: окна у них нет, а работа идёт.

  Application? _app;

  /// Команды в порядке установки — то, что увидит список команд.
  @override
  List<AppCommand> get installed => List.unmodifiable(_prototypes.values);

  /// Все привязки в порядке приоритета.
  @override
  List<KeyBinding> get bindings => List.unmodifiable(_bindings);

  /// Запущенные команды, которым нужно окно. Ядро рисует их поверх приложения.

  // --- Фоновые работы ---

  final List<OperationRun> _runs = [];

  @override
  List<OperationRun> get all => List.unmodifiable(_runs);

  @override
  List<OperationRun> at(ViewportPosition position) => [
    for (final run in _runs)
      if (run.owner == position) run,
  ];

  @override
  OperationRun? byId(String runId) => _runs.where((run) => run.runId == runId).firstOrNull;

  @override
  void register(OperationRun run) {
    _runs
      ..removeWhere((existing) => existing.runId == run.runId)
      ..add(run);
    notifyListeners();
  }

  @override
  void forget(String runId) {
    final before = _runs.length;
    _runs.removeWhere((run) => run.runId == runId);
    if (_runs.length != before) {
      notifyListeners();
    }
  }

  /// Убирает окно команды, оставляя работу идти.
  ///
  /// Прятать можно только то, что умеет рассказать о себе: иначе работа
  /// исчезла бы с глаз без следа.
  @override
  void sendToBackground(String runId, {required ViewportPosition owner}) {
    final run = byId(runId);
    if (run == null) {
      return;
    }

    // Убрать окно — дело того, кто его показал: реестру остаётся запомнить,
    // где показывать полоску.
    run.owner = owner;
    notifyListeners();
  }

  /// Возвращает окно работы, ушедшей в фон.
  ///
  /// Так операция, задавшая вопрос, снова оказывается на виду: ответить за
  /// пользователя ядро не вправе.
  @override
  void bringToFront(String runId) {
    final run = byId(runId);
    if (run?.bringToFront case final show?) {
      run!.owner = null;
      show();
      notifyListeners();
    }
  }

  /// Связывает реестр с приложением и создаёт прототипы команд.
  void attach(Application app) {
    _app = app;
    for (var i = 0; i < _factories.length; i++) {
      final factory = _factories[i];
      final command = factory();
      command.bind(app);
      if (!command.init(app)) {
        continue;
      }
      _prototypes[command.id] = command;
      _factoryById[command.id] = factory;
      if (i < _owners.length) {
        _ownerOf[command.id] = _owners[i];
      }
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
  /// Клавиша принадлежит содержимому активной области — тому, что сейчас на
  /// экране. Исключение одно, и оно описано ниже: функциональные клавиши при
  /// вводе в командной строке.
  @override
  KeyBinding? bindingFor(KeyCombination combination) {
    final app = _app;
    if (app == null) {
      return null;
    }

    final view = app.view;
    final active = view.activeArea;
    final found = _lookup(combination, view.contentAt(active));
    if (found != null || active != ViewportPosition.bottom || !_beyondTextInput(combination)) {
      return found;
    }

    // Клавиша, которой у однострочного поля нет, достаётся панели.
    //
    // Внизу командная строка, а панели никуда не делись — они на экране, и ряд
    // кнопок под строкой обещает именно их команды: без этого он пустел бы
    // весь, стоило начать набирать. Стрелки вверх и вниз там же и по той же
    // причине: в строке им ходить некуда, а выбрать файл посреди набора
    // команды нужно постоянно.
    //
    // Перечень, а не общее «не нашлось — поищем у панели»: общий откат отдал бы
    // панели и букву — привязка любого символа требует, чтобы содержимым была
    // панель, а здесь мы ровно панель и подставляем, — и быстрый поиск ожил бы
    // посреди набора. То же с `Enter` и `Bsp`: это клавиши строки.
    return _lookup(combination, view.contentAt(view.sourceArea));
  }

  /// Клавиша, которой в однострочном поле ввода делать нечего.
  static bool _beyondTextInput(KeyCombination combination) =>
      combination.isFunctionKey || combination.key == 'Up' || combination.key == 'Down';

  /// Привязка, подходящая под комбинацию при таком содержимом активной области.
  ///
  /// Сначала та, чья команда действительно выполнится; если такой нет —
  /// первая подходящая, чтобы кнопка нижней панели показала название и
  /// осталась приглушённой.
  KeyBinding? _lookup(KeyCombination combination, ViewportState? content) {
    final app = _app!;
    final node = app.activePanel.currentNode;
    KeyBinding? fallback;

    for (final binding in _bindings) {
      // Клавиша принадлежит тому, что сейчас на экране: `F5` не должен
      // копировать файлы из-под открытого просмотрщика, а ряд кнопок —
      // обещать то, чего по нажатию не будет.
      if (!binding.matches(combination, node, content: content)) {
        continue;
      }
      final command = _prototypes[binding.commandId];
      if (command == null) {
        // Привязка к неизвестной команде: могла остаться от старых настроек.
        continue;
      }
      // Выполнимость спрашивается с теми же значениями, с какими команда по
      // этой клавише и запустится: `Cmd+F2` про правую панель, и занятость
      // левой ему не помеха.
      final invocation = CommandInvocation(parameters: binding.parametersFor(combination));
      if (command.isExecutable(CommandContext.of(app, invocation))) {
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
    return run(binding.commandId, CommandInvocation(parameters: binding.parametersFor(combination)));
  }

  /// Запускает команду по идентификатору — с клавиатуры, кнопкой, из меню или
  /// из списка команд. Результат всюду одинаковый.
  ///
  /// Запускает прототип: состояния прогона у команды нет, и второй экземпляр
  /// ей не нужен. Всё, с чем её вызвали, лежит в [invocation].
  @override
  bool run(String commandId, [CommandInvocation invocation = const CommandInvocation()]) {
    final app = _app;
    final command = _prototypes[commandId];
    if (app == null || command == null) {
      return false;
    }
    // Выполнимость спрашивают про этот запуск: «открыть путь в левой» и «в
    // правой» — одна команда, а заняты панели порознь.
    final context = CommandContext.of(app, invocation);
    if (!command.isExecutable(context)) {
      return false;
    }

    // Запуск не ждут: нажатие клавиши не может стоять и ждать конца работы.
    // Но исход разбирается — раньше ошибка команды без окна пропадала совсем.
    unawaited(runToCompletion(command, invocation));
    return true;
  }

  /// Выполняет уже созданную команду и разбирает исход: закрывает окно, если
  /// оно было, и сообщает об ошибке.
  ///
  /// Публичный, потому что запускают команды не только клавишей: этим же путём
  /// идут стартовые команды модулей при сборке приложения. Ошибка наружу не
  /// пробрасывается, а уходит в [onError] — упавшая команда одного модуля не
  /// должна ронять остальные.
  Future<void> runToCompletion(AppCommand command, [CommandInvocation invocation = const CommandInvocation()]) async {
    Object? failure;
    try {
      await command.execute(CommandContext.of(_app!, invocation));
    } catch (error) {
      failure = error;
    }

    _afterRun(command, failure);
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
    command.bind(app);
    return command;
  }

  @override
  bool isExecutable(AppCommand command, [CommandInvocation invocation = const CommandInvocation()]) {
    return _app != null && command.isExecutable(CommandContext.of(_app!, invocation));
  }

  CommandContext contextFor(AppCommand command) => CommandContext.of(_app!);

  Future<void> shutdown() async {
    for (final command in _prototypes.values) {
      await command.shutdown();
    }
  }

  // --- Запуск: что делается до работы и после неё ---
  //
  // Один путь на все способы вызова: клавишей, кнопкой, из списка команд или
  // при сборке приложения. Поэтому окно учитывается и исход разбирается
  // одинаково, кто бы команду ни запустил.

  /// Разбирает исход: ошибка уходит в [onError].
  ///
  /// Окно здесь не при чём: им распоряжается тот, кто его показал, — сама
  /// команда.
  void _afterRun(AppCommand command, Object? error) {
    if (error != null) {
      onError?.call(error, command);
    }
  }
}
