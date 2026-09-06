import 'dart:async';

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
  String get label => tr('Panel view');

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

  @override
  String get label => tr('Panel view…');

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
