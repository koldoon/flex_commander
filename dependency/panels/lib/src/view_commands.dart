import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

import 'tree_view.dart';

/// Показать каталог другим видом.
///
/// Спецификация — `docs/spec/panel-views.md`.
///
/// Одна команда с доводом, а не по команде на вид: вид называется параметром,
/// и модуль, объявивший вид, привязывает к нему свою клавишу сам. Панель тоже
/// доводом — как в окне адреса.
class SetPanelViewCommand extends AppCommand {
  static const String commandId = 'panel.view.set';

  /// Имя вида: `table`, `brief`, `tree`.
  static const String viewParam = 'view';

  /// Какая панель; не сказано — активная.
  static const String panelParam = 'panel';
  static const String leftPanel = 'left';
  static const String rightPanel = 'right';

  @override
  String get id => commandId;

  @override
  String get label => tr('Set panel view');

  @override
  String get description => tr('Show the directory another way');

  @override
  Set<String> get keywords => const {'layout', 'brief', 'tree', 'icons', 'columns'};

  /// Панель, о которой идёт речь.
  static Panel panelOf(CommandContext context) => switch (context.invocation.param<String>(panelParam)) {
    leftPanel => context.app.left,
    rightPanel => context.app.right,
    _ => context.panel,
  };

  /// Вид, названный вызовом; пусто — вида не назвали.
  static String viewOf(CommandContext context) => context.invocation.param<String>(viewParam) ?? '';

  /// Выполнима, только если такой вид объявлен: клавиша, привязанная к виду
  /// выключенного модуля, не должна обещать несбыточного.
  @override
  bool isExecutable(CommandContext context) {
    final view = viewOf(context);
    return view.isNotEmpty && context.app.panelViews.byId(view) != null;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final view = viewOf(context);
    if (view.isEmpty) {
      return;
    }
    await switchTo(panelOf(context), view);
  }

  /// Сменить вид, запомнив прежний.
  ///
  /// Помнится ради дерева: `Enter` в нём открывает каталог и уходит в список —
  /// в тот, который человек выбрал сам, а не в таблицу заодно
  /// (`docs/spec/panel-view-tree.md`, §6). Это состояние сеанса, а не
  /// настройка: помнить его между запусками незачем.
  static Future<void> switchTo(Panel panel, String view) async {
    if (panel.view != view) {
      _previous[panel.id] = panel.view;
    }
    await panel.setView(view);
  }

  /// Вид, который стоял в этой панели до нынешнего; null — не меняли.
  static String? previousOf(Panel panel) => _previous[panel.id];

  static final Map<PanelId, String> _previous = {};
}

/// Выбрать вид панели из объявленных — окном.
///
/// `Alt-F1` и `Alt-F2` — привычка `mc`, где ими меняют то, что видно в левой и
/// правой панели, не трогая соседнюю.
class ChoosePanelViewCommand extends AppCommand {
  static const String commandId = 'panel.view.choose';

  @override
  String get id => commandId;

  // Без многоточия: оно значит «спросит и откроет окно» в **меню**, а здесь
  // им же названо само окно — открытому окну обещать нечего. Прочие команды с
  // окнами у нас тоже без него: «Address», «Find files», «Copy».
  @override
  String get label => tr('Panel view');

  @override
  String get description => tr('Choose how this panel shows the directory');

  @override
  Set<String> get keywords => const {'layout', 'brief', 'tree', 'icons', 'columns'};

  /// Есть из чего выбирать: без модулей, объявивших виды, окно показало бы
  /// пустоту.
  @override
  bool isExecutable(CommandContext context) => context.app.panelViews.available.isNotEmpty;

  /// Окно встаёт **над своей панелью** — как окно адреса, и по той же причине:
  /// «вид левой» и «вид правой» иначе неотличимы на вид, а заголовок читают не
  /// в первую очередь.
  DialogArea areaOf(CommandContext context) {
    final ratio = context.app.splitRatio;
    final left = identical(SetPanelViewCommand.panelOf(context), context.app.left);
    return left ? DialogArea(end: ratio) : DialogArea(start: ratio);
  }

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final panel = SetPanelViewCommand.panelOf(context);
    final state = ViewPickerState(views: app.panelViews.available, current: panel.view);

    late final String dialogId;
    void close() => app.view.closeDialog(dialogId);
    void apply() {
      close();
      unawaited(SetPanelViewCommand.switchTo(panel, state.selected.id));
    }

    state.apply = apply;
    state.close = close;
    dialogId = app.view.showDialog(
      DialogSpec(
        title: label,
        takesFocus: true,
        area: areaOf(context),
        content: _ViewPicker(state: state),
        // `Enter` разбирает рама окна — как и во всех окнах приложения; здесь
        // он значит «показать выбранное».
        onSubmit: apply,
        onDismiss: close,
      ),
    );
  }
}

/// Что выбрано в окне выбора вида.
///
/// Состоянием, а не полем виджета: `Enter` разбирает рама окна, и к моменту
/// ответа выбранное должно лежать там, откуда его возьмут, — то же правило, что
/// у окна маски и окна адреса.
class ViewPickerState extends ChangeNotifier {
  ViewPickerState({required this.views, required String current})
    : _index = views.indexWhere((view) => view.id == current).clamp(0, views.isEmpty ? 0 : views.length - 1);

  final List<PanelViewSpec> views;

  int _index;

  int get index => _index;

  set index(int value) {
    if (value == _index || value < 0 || value >= views.length) {
      return;
    }
    _index = value;
    notifyListeners();
  }

  PanelViewSpec get selected => views[_index];

  /// Показать выбранное: зовёт и `Enter` рамы, и щелчок по строке.
  VoidCallback apply = _nothing;

  /// Закрыть, ничего не меняя: кнопка «Отмена» и `Esc`.
  VoidCallback close = _nothing;

  static void _nothing() {}
}

/// Список видов: имя, пояснение, курсор на том, который стоит сейчас.
class _ViewPicker extends StatefulWidget {
  const _ViewPicker({required this.state});

  final ViewPickerState state;

  @override
  State<_ViewPicker> createState() => _ViewPickerState();
}

class _ViewPickerState extends State<_ViewPicker> {
  /// Свой узел фокуса, а не `autofocus`: фокус в открытом окне забирает его
  /// рама, и `autofocus` до списка не доходит. Стрелки при этом остаются
  /// здесь, а `Enter` и `Esc` уходят выше — раме, как и задумано.
  final FocusNode _focus = FocusNode(debugLabel: 'panel views');

  /// Размер страницы для `PgUp`/`PgDn`: список меряет обзор и кладёт его сюда.
  final FcPickPage _page = FcPickPage();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final moved = FcPickList.moveSelection(
      event,
      selected: widget.state.index,
      count: widget.state.views.length,
      page: _page,
    );
    if (moved == null || moved < 0) {
      return KeyEventResult.ignored;
    }
    widget.state.index = moved;
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = FcTheme.of(context);
    final state = widget.state;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: state,
        builder:
            (context, _) => CommandDialogForm(
              onCancel: state.close,
              onSubmit: state.apply,
              submitLabel: strings.tr('Show'),
              children: [
                CommandDialogField.bleed(
                  child: SizedBox(
                    // Место отмеряется строками, как в списке недавних адресов:
                    // видов немного, и прокручиваться тут нечему.
                    height: (theme.metrics.rowHeight + theme.metrics.rowGap) * state.views.length,
                    child: FcPickList(
                      rows: [
                        for (final view in state.views)
                          FcPickRow(
                            id: view.id,
                            // Названия видов приходят значением — переводит их
                            // тот, кто показывает.
                            title: strings.tr(view.title),
                            subtitle: strings.tr(view.description),
                          ),
                      ],
                      query: '',
                      selected: state.index,
                      page: _page,
                      onTap: (id) {
                        state.index = state.views.indexWhere((view) => view.id == id);
                        state.apply();
                      },
                    ),
                  ),
                ),
                // Настройки выбранного вида — под списком, и меняются вместе с
                // выбором: человек видит, что достанется тому, что он сейчас
                // включит.
                if (state.selected.options case final options?) CommandDialogField.wide(child: options(context)),
              ],
            ),
      ),
    );
  }
}

/// Шаг курсора по столбцу — влево и вправо.
///
/// Отдельные команды, а не «если вид краткий» внутри хода по строке: там, где
/// столбцов нет, команда невыполнима, и клавиша достаётся объявленным следом —
/// нынешним «в начало» и «в конец» (`docs/spec/panel-views.md`, §10).
class MoveCursorColumnCommand extends AppCommand {
  MoveCursorColumnCommand({required this.right});

  static const String leftId = 'panel.cursor.columnLeft';
  static const String rightId = 'panel.cursor.columnRight';

  final bool right;

  @override
  String get id => right ? rightId : leftId;

  @override
  String get label => right ? tr('Column right') : tr('Column left');

  @override
  String get description => tr('Move the cursor one column aside');

  /// Спрашивается не вид, а его раскладка: столбцы объявляет сам вид
  /// (`Panel.columnRows`), и команде всё равно, кто это — краткий вид или
  /// будущие столбцы Finder.
  @override
  bool isExecutable(CommandContext context) => context.panel.columnRows > 0 && context.panel.entries.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final rows = panel.columnRows;
    if (rows <= 0) {
      return;
    }
    // У края список упирается, а не заворачивает: заворот выглядел бы скачком
    // через весь экран.
    final target = panel.cursorIndex + (right ? rows : -rows);
    panel.setCursorIndex(target.clamp(0, panel.entries.length - 1));
  }
}

/// Раскрыть или свернуть ветвь дерева — и шагнуть внутрь или наружу.
///
/// Свои команды, а не ход по столбцам: смысл другой, а `Left` и `Right` те же.
/// Там, где дерева нет, они невыполнимы, и клавиша достаётся объявленным
/// следом (`docs/spec/panel-view-tree.md`, §6).
class TreeBranchCommand extends AppCommand {
  TreeBranchCommand({required this.expand});

  static const String expandId = 'panel.tree.expand';
  static const String collapseId = 'panel.tree.collapse';

  final bool expand;

  @override
  String get id => expand ? expandId : collapseId;

  @override
  String get label => expand ? tr('Expand branch') : tr('Collapse branch');

  @override
  String get description => expand ? tr('Open the branch, or step into it') : tr('Close the branch, or step out of it');

  /// Дерево спрашивается у того, кто его рисует: команда не знает, какой сейчас
  /// вид, — она знает, что перед ней дерево.
  @override
  bool isExecutable(CommandContext context) => treeOf(context.app, context.panel) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final tree = treeOf(context.app, context.panel);
    if (tree == null) {
      return;
    }
    if (expand) {
      await tree.expand();
    } else {
      tree.collapse();
    }
  }

  /// Дерево этой панели, если оно сейчас на экране.
  static TreeViewState? treeOf(Application app, Panel panel) => PanelTrees.of(panel);
}

/// Открыть каталог под курсором дерева и уйти в список.
class OpenTreeBranchCommand extends AppCommand {
  static const String commandId = 'panel.tree.open';

  @override
  String get id => commandId;

  @override
  String get label => tr('Open branch');

  @override
  String get description => tr('Open the directory and go back to the list');

  @override
  bool isExecutable(CommandContext context) => PanelTrees.of(context.panel) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final tree = PanelTrees.of(context.panel);
    // Возвращаемся к тому виду, который стоял до дерева: человек выбрал его
    // сам, и подменять его таблицей было бы самоуправством.
    tree?.submit(SetPanelViewCommand.previousOf(context.panel) ?? PanelSettings.defaultView);
  }
}

/// Курсор по ветвям дерева.
///
/// Свои команды, а не панельные: в дереве курсор свой — он ходит по ветвям, а
/// не по строкам списка. Объявлены раньше панельных, и там, где дерева нет,
/// невыполнимы (`docs/spec/panel-view-tree.md`, §6).
class MoveTreeCursorCommand extends AppCommand {
  MoveTreeCursorCommand(this.step);

  /// Куда шагнуть; шаг страницы и края — те же клавиши, что в списке.
  final TreeStep step;

  @override
  String get id => switch (step) {
    TreeStep.up => 'panel.tree.cursorUp',
    TreeStep.down => 'panel.tree.cursorDown',
    TreeStep.pageUp => 'panel.tree.pageUp',
    TreeStep.pageDown => 'panel.tree.pageDown',
    TreeStep.first => 'panel.tree.first',
    TreeStep.last => 'panel.tree.last',
  };

  @override
  String get label => switch (step) {
    TreeStep.up => tr('Branch up'),
    TreeStep.down => tr('Branch down'),
    TreeStep.pageUp => tr('Branches page up'),
    TreeStep.pageDown => tr('Branches page down'),
    TreeStep.first => tr('First branch'),
    TreeStep.last => tr('Last branch'),
  };

  @override
  bool isExecutable(CommandContext context) => PanelTrees.of(context.panel) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final tree = PanelTrees.of(context.panel);
    if (tree == null) {
      return;
    }
    // Страница — то, что видно, минус строка перекрытия: то же правило, что у
    // списка файлов.
    final page = (context.panel.pageSize - 1).clamp(1, context.panel.pageSize);
    tree.moveCursor(switch (step) {
      TreeStep.up => tree.cursor - 1,
      TreeStep.down => tree.cursor + 1,
      TreeStep.pageUp => tree.cursor - page,
      TreeStep.pageDown => tree.cursor + page,
      TreeStep.first => 0,
      TreeStep.last => tree.visibleRows - 1,
    });
  }
}

/// Куда шагает курсор дерева.
enum TreeStep { up, down, pageUp, pageDown, first, last }
