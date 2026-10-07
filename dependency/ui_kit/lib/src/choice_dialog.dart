import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

import 'app_scope.dart';
import 'command_dialog.dart';
import 'fc_theme.dart';
import 'pick_list.dart';

/// Окно выбора из короткого списка, где выбранное видно **сразу**.
///
/// Стрелки по списку зовут [onChoose] на каждом шаге — показ под окном
/// перестраивается, пока человек выбирает. `Enter` и «OK» оставляют выбранное,
/// `Esc` и «Cancel» зовут [onChoose] с тем, что было до окна. Так выбирают
/// соотношение сторон ролика и кодировку текста
/// (`docs/spec/text-encodings.md`, §8).
///
/// Возвращает номер окна.
String showChoiceDialog<T>({
  required ApplicationView view,
  required String title,
  required List<T> items,
  required String Function(T item) labelOf,
  required T current,
  required void Function(T item) onChoose,
}) {
  final state = _ChoiceState<T>(items: items, current: current, onChoose: onChoose);
  late final String dialogId;
  void close() => view.closeDialog(dialogId);
  state.apply = close;
  state.cancel = () {
    state.revert();
    close();
  };
  dialogId = view.showDialog(
    DialogSpec(
      title: title,
      takesFocus: true,
      hugsContent: true,
      content: _ChoiceList<T>(state: state, labelOf: labelOf),
      onSubmit: state.apply,
      onDismiss: state.cancel,
    ),
  );
  return dialogId;
}

/// Что выбрано. Состоянием, а не полем виджета: `Enter` разбирает рама окна.
class _ChoiceState<T> extends ChangeNotifier {
  _ChoiceState({required this.items, required T current, required this.onChoose})
    : _before = current,
      _index = items.indexOf(current).clamp(0, items.length - 1);

  final List<T> items;
  final void Function(T item) onChoose;
  final T _before;

  int get index => _index;
  int _index;

  set index(int value) {
    if (value == _index || value < 0 || value >= items.length) {
      return;
    }
    _index = value;
    onChoose(items[value]);
    notifyListeners();
  }

  void revert() => onChoose(_before);

  VoidCallback apply = _nothing;
  VoidCallback cancel = _nothing;

  static void _nothing() {}
}

/// Список — тем же устройством, что окно выбора вида панели.
class _ChoiceList<T> extends StatefulWidget {
  const _ChoiceList({super.key, required this.state, required this.labelOf});

  final _ChoiceState<T> state;
  final String Function(T item) labelOf;

  @override
  State<_ChoiceList<T>> createState() => _ChoiceListState<T>();
}

class _ChoiceListState<T> extends State<_ChoiceList<T>> {
  /// Свой узел фокуса: фокус открытого окна забирает рама, и `autofocus` до
  /// списка не доходит. Стрелки остаются здесь, `Enter` и `Esc` — раме.
  final FocusNode _focus = FocusNode(debugLabel: 'choice');

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
      count: widget.state.items.length,
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
              onCancel: state.cancel,
              onSubmit: state.apply,
              submitLabel: strings.tr('OK'),
              children: [
                CommandDialogField.bleed(
                  child: SizedBox(
                    // Список короткий: место отмеряется строками, и
                    // прокручиваться тут нечему.
                    height: (theme.metrics.rowHeight + theme.metrics.rowGap) * state.items.length,
                    child: FcPickList(
                      hugged: true,
                      textInset: theme.metrics.dialogHorizontalPadding,
                      rows: [
                        for (var i = 0; i < state.items.length; i++)
                          FcPickRow(id: '$i', title: widget.labelOf(state.items[i])),
                      ],
                      query: '',
                      selected: state.index,
                      page: _page,
                      onTap: (id) => state.index = int.parse(id),
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
