import 'package:fc_ui_api/fc_ui_api.dart';

import 'panels_settings.dart';

/// Команды вкладок (`docs/spec/panel-tabs.md`).
///
/// Все они про **сторону, в которой стоит курсор**: вкладка — это то, что
/// человек считает одной панелью, и заводят её там, где работают. Соседняя
/// сторона живёт своим рядом.
///
/// Сторона берётся у рабочей области, а не у панели: под наложением — быстрым
/// просмотром, просмотрщиком — панели не видно, и вкладки там ни при чём.
ViewportPosition? _sideOf(CommandContext context) => context.app.view.positionOf(context.panel);

/// Новая вкладка на текущем каталоге.
class NewTabCommand extends AppCommand {
  NewTabCommand({required this.settings});

  static const String commandId = 'panel.tabs.new';

  /// Настройки видов: предел числа вкладок. Способом узнать, а не значением —
  /// его правят в окне настроек, и следующее же нажатие обязано его учесть.
  final PanelsSettings Function() settings;

  @override
  String get id => commandId;

  @override
  String get label => tr('New tab');

  @override
  String get description => tr('Open one more tab on the current directory');

  @override
  Set<String> get keywords => const {'panel', 'duplicate', 'split'};

  @override
  bool isExecutable(CommandContext context) {
    final side = _sideOf(context);
    if (side == null) {
      return false;
    }
    // Предел — не придирка: вкладка держит аренду, а пять архивов это пять
    // распакованных копий (`docs/spec/panel-tabs.md`, §7).
    return context.app.tabsAt(side).length < settings().maxTabs;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final side = _sideOf(context);
    if (side == null) {
      return;
    }
    final tabs = context.app.tabsAt(side);
    final at = tabs.indexWhere((tab) => identical(tab.panel, context.panel));
    // Рядом с нынешней, а не в конце ряда: новая вкладка про то же место.
    await context.app.openTab(side, like: context.panel, at: at < 0 ? null : at + 1);
  }
}

/// Закрыть текущую вкладку.
class CloseTabCommand extends AppCommand {
  static const String commandId = 'panel.tabs.close';

  @override
  String get id => commandId;

  @override
  String get label => tr('Close tab');

  @override
  String get description => tr('Close this tab and let its source go');

  @override
  Set<String> get keywords => const {'panel'};

  /// Последняя не закрывается: сторона без панели — состояние, которого в
  /// модели нет вовсе.
  @override
  bool isExecutable(CommandContext context) {
    final side = _sideOf(context);
    return side != null && context.app.tabsAt(side).length > 1;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final tab = context.app.tabOf(context.panel);
    if (tab != null) {
      context.app.closeTab(tab);
    }
  }
}

/// Соседняя вкладка — по кругу.
class CycleTabsCommand extends AppCommand {
  CycleTabsCommand({required this.forward});

  static const String nextId = 'panel.tabs.next';
  static const String previousId = 'panel.tabs.previous';

  final bool forward;

  @override
  String get id => forward ? nextId : previousId;

  @override
  String get label => forward ? tr('Next tab') : tr('Previous tab');

  @override
  String get description => tr('Switch to the neighbouring tab');

  @override
  Set<String> get keywords => const {'switch', 'cycle'};

  @override
  bool isExecutable(CommandContext context) {
    final side = _sideOf(context);
    return side != null && context.app.tabsAt(side).length > 1;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final side = _sideOf(context);
    if (side == null) {
      return;
    }
    final tabs = context.app.tabsAt(side);
    final at = tabs.indexWhere((tab) => identical(tab.panel, context.panel));
    if (at < 0) {
      return;
    }
    // По кругу: ряд короткий, и упираться в его край незачем.
    context.app.showTab(tabs[(at + (forward ? 1 : -1) + tabs.length) % tabs.length]);
  }
}

/// Вкладка по номеру: `Alt-1`…`Alt-9`.
class SelectTabCommand extends AppCommand {
  static const String commandId = 'panel.tabs.select';

  /// Номер вкладки, считая с единицы.
  static const String numberParam = 'number';

  @override
  String get id => commandId;

  @override
  String get label => tr('Tab by number');

  @override
  String get description => tr('Show the tab with this number');

  @override
  Set<String> get keywords => const {'switch', 'cycle'};

  static int _numberOf(CommandContext context) =>
      int.tryParse(context.invocation.param<String>(numberParam) ?? '') ?? 0;

  @override
  bool isExecutable(CommandContext context) {
    final side = _sideOf(context);
    if (side == null) {
      return false;
    }
    final number = _numberOf(context);
    // Клавиша с номером, которому вкладки нет, ничего не делает — и не мешает
    // тому, кто объявлен следом.
    return number >= 1 && number <= context.app.tabsAt(side).length;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final side = _sideOf(context);
    if (side == null) {
      return;
    }
    final tabs = context.app.tabsAt(side);
    final number = _numberOf(context);
    if (number >= 1 && number <= tabs.length) {
      context.app.showTab(tabs[number - 1]);
    }
  }
}

/// Закрепить вкладку или отпустить.
class ToggleTabLockCommand extends AppCommand {
  static const String commandId = 'panel.tabs.toggleLock';

  @override
  String get id => commandId;

  @override
  String get label => tr('Pin tab');

  @override
  String get description => tr('A pinned tab stays on its directory; leaving it opens a new one');

  @override
  Set<String> get keywords => const {'lock', 'keep'};

  @override
  bool isExecutable(CommandContext context) => context.app.tabOf(context.panel) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final tab = context.app.tabOf(context.panel);
    if (tab != null) {
      context.app.setTabPinned(tab, !tab.pinned);
    }
  }
}
