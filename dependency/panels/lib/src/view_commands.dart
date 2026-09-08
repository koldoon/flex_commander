import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

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
    await panelOf(context).setView(view);
  }
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
    final state = ViewPickerState(views: app.panelViews.available, current: panel.view, panel: panel);

    late final String dialogId;
    void close() => app.view.closeDialog(dialogId);
    void apply() {
      close();
      unawaited(panel.setView(state.selected.id));
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
  ViewPickerState({required this.views, required String current, required this.panel})
    : _index = views.indexWhere((view) => view.id == current).clamp(0, views.isEmpty ? 0 : views.length - 1);

  final List<PanelViewSpec> views;

  /// Панель, для которой открыли окно: её правят панельные настройки вида —
  /// колонки таблицы (`docs/spec/panel-views.md`, §7).
  final Panel panel;

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
              submitLabel: strings.tr('OK'),
              children: [
                CommandDialogField.bleed(
                  child: SizedBox(
                    // Место отмеряется строками, как в списке недавних адресов:
                    // видов немного, и прокручиваться тут нечему.
                    height: (theme.metrics.rowHeight + theme.metrics.rowGap) * state.views.length,
                    child: FcPickList(
                      // Обычный отступ содержимого окна, а не тот, что под
                      // полем ввода: поля здесь нет вовсе. Увеличенный нужен
                      // там, где список **дополняет** набранное и текст обязан
                      // стоять единой колонкой с ним, — в палитре и в истории
                      // адресов.
                      textInset: theme.metrics.dialogHorizontalPadding,
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
                if (state.selected.options case final options?)
                  CommandDialogField.wide(child: options(context, state.panel)),
              ],
            ),
      ),
    );
  }
}

/// Раскрыть или свернуть ветвь **вместе со всем, что под ней**.
///
/// Четыре команды одним классом: поддерево под курсором и всё дерево, каждое —
/// в обе стороны. Одним, потому что различие в двух словах, а поведение общее:
/// ветвь называется путём, пустой путь значит «всё»
/// (`docs/spec/panel-view-tree.md`, §6а).
class TreeDeepCommand extends AppCommand {
  TreeDeepCommand({required this.expand, required this.all});

  static const String expandSubtreeId = 'panel.tree.expandSubtree';
  static const String collapseSubtreeId = 'panel.tree.collapseSubtree';
  static const String expandAllId = 'panel.tree.expandAll';
  static const String collapseAllId = 'panel.tree.collapseAll';

  /// Раскрыть или свернуть.
  final bool expand;

  /// Всё дерево или только поддерево под курсором.
  final bool all;

  @override
  String get id => switch ((expand, all)) {
    (true, true) => expandAllId,
    (true, false) => expandSubtreeId,
    (false, true) => collapseAllId,
    (false, false) => collapseSubtreeId,
  };

  @override
  String get label => switch ((expand, all)) {
    (true, true) => tr('Expand all'),
    (true, false) => tr('Expand subtree'),
    (false, true) => tr('Collapse all'),
    (false, false) => tr('Collapse subtree'),
  };

  @override
  String get description => switch ((expand, all)) {
    (true, true) => tr('Open every branch of the tree — up to a limit'),
    (true, false) => tr('Open the branch under the cursor and everything inside it'),
    (false, true) => tr('Close every branch, leaving the roots'),
    (false, false) => tr('Close the branch under the cursor and everything inside it'),
  };

  @override
  Set<String> get keywords => const {'branches', 'unfold', 'fold'};

  /// Спрашивается **набор строк**, а не вид: перед командой дерево или нет.
  ///
  /// Над файлом она тоже выполнима, и не по недосмотру: свернуть там нечего, и
  /// сворачивание уводит курсор к ветви, в которой строка лежит, — ровно как
  /// обычное (`docs/spec/panel-view-tree.md`, §6).
  @override
  bool isExecutable(CommandContext context) => context.panel.rows == RowsKind.tree;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    if (all) {
      await _open(context, '');
      return;
    }

    final row = panel.currentEntry;
    if (row == null) {
      return;
    }
    // Раскрывать нечего — над файлом и над «..» ветви нет.
    if (expand) {
      if (row.isDirectory && row.path.isNotEmpty) {
        await _open(context, row.path);
      }
      return;
    }
    // Свернуть есть что — сворачиваем всё, что под ветвью; нечего — выходим к
    // ветви, в которой строка лежит.
    if (row.isOpen) {
      await _open(context, row.path);
      return;
    }
    final at = TreeBranchCommand.parentRowOf(panel);
    if (at >= 0) {
      panel.setCursorIndex(at);
    }
  }

  /// Раскрыть или свернуть — и сказать, если раскрытие упёрлось в предел.
  ///
  /// Тостом, а не строкой состояния: строка говорит о том, что **идёт**, и
  /// сообщение осталось бы висеть в ней, пока его не сменят.
  Future<void> _open(CommandContext context, String path) async {
    final result = await context.panel.expandDeep(path, expanded: expand);
    if (!result.stopped) {
      return;
    }
    context.app.toasts.show(tr('Expanded {count} branches — the rest by hand', args: {'count': result.opened}));
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

/// Раскрыть или свернуть ветвь дерева.
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
  String get description =>
      expand
          ? tr('Expand the branch under the cursor')
          : tr('Collapse the branch, or step out to the directory it lies in');

  /// Спрашивается **набор строк**, а не вид: строки собирает ядро, и команда
  /// знает лишь то, что перед ней дерево (`docs/spec/panel-node-list.md`, §3).
  @override
  bool isExecutable(CommandContext context) => context.panel.rows == RowsKind.tree;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final row = panel.currentEntry;
    if (row == null) {
      return;
    }

    if (expand) {
      if (row.isDirectory && !row.isOpen) {
        panel.setExpanded(row.path, expanded: true);
      } else if (row.isOpen) {
        // Раскрытая ветвь — шаг внутрь: следующая строка и есть её первый
        // ребёнок.
        panel.setCursorIndex(panel.cursorIndex + 1);
      }
      return;
    }

    if (row.isOpen) {
      panel.setExpanded(row.path, expanded: false);
      return;
    }
    // Свернуть нечего — выходим к ветви, в которой строка лежит: по глубине,
    // потому что строки уже разложены деревом (`panel-view-tree.md`, §6).
    final at = parentRowOf(panel);
    if (at >= 0) {
      panel.setCursorIndex(at);
    }
  }

  /// Строка ветви, в которой лежит строка под курсором; -1 — такой нет.
  ///
  /// Общая с [TreeDeepCommand]: «свернуть нечего — выйти к своей ветви» —
  /// одно правило на обе, и расходиться им незачем.
  static int parentRowOf(Panel panel) {
    final rows = panel.entries;
    final at = panel.cursorIndex;
    if (at < 0 || at >= rows.length) {
      return -1;
    }
    for (var i = at - 1; i >= 0; i--) {
      if (rows[i].level < rows[at].level) {
        return i;
      }
    }
    return -1;
  }
}

/// Раскрыть ветвь под курсором; раскрытую — свернуть.
///
/// `Enter` привычен по спискам, `Right` и `Left` — по деревьям, и спорить с
/// обеими привычками незачем: делают они одно и то же
/// (`docs/spec/panel-view-tree.md`, §6).
class ToggleTreeBranchCommand extends AppCommand {
  static const String commandId = 'panel.tree.toggle';

  @override
  String get id => commandId;

  @override
  String get label => tr('Toggle branch');

  @override
  String get description => tr('Expand the branch, or collapse it back');

  /// Только над ветвью: над прочими строками клавиша достаётся тем, кто
  /// объявлен следом.
  ///
  /// Прежде команда объявляла себя выполнимой над **любой** строкой дерева, а
  /// в теле молча выходила — и `Enter` над файлом и над ссылкой не делал
  /// ничего вовсе: до навигации он не доходил.
  @override
  bool isExecutable(CommandContext context) =>
      context.panel.rows == RowsKind.tree && (context.panel.currentEntry?.isDirectory ?? false);

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final row = panel.currentEntry;
    if (row == null || !row.isDirectory) {
      return;
    }
    panel.setExpanded(row.path, expanded: !row.isOpen);
  }
}

/// `Enter` над ссылкой в дереве: перейти к тому, куда она ведёт.
///
/// Раскрыть ссылку нельзя — она увела бы в цикл, — а сходить по ней можно:
/// курсор встаёт на цель, а ветви до неё раскрываются
/// (`docs/spec/panel-view-tree.md`, §4а).
class TreeFollowLinkCommand extends AppCommand {
  static const String commandId = 'panel.tree.followLink';

  @override
  String get id => commandId;

  @override
  String get label => tr('Go to link target');

  @override
  String get description => tr('Move the cursor to what the link points at');

  @override
  Set<String> get keywords => const {'symlink', 'resolve', 'follow'};

  /// Только в дереве и только над ссылкой: в списке `Enter` над ссылкой значит
  /// «войти», и менять это незачем.
  @override
  bool isExecutable(CommandContext context) =>
      context.panel.rows == RowsKind.tree && (context.panel.currentEntry?.isLink ?? false);

  @override
  Future<void> execute(CommandContext context) async {
    final entry = context.panel.currentEntry;
    if (entry == null || entry.path.isEmpty) {
      return;
    }
    if (await context.panel.followLink(entry.path)) {
      return;
    }
    // Битая ссылка — «случилось и закончилось»: тост, а не строка состояния.
    context.app.toasts.show(tr('The link leads nowhere: {name}', args: {'name': entry.name}));
  }
}
