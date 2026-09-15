import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import '../state/commands/session_commands.dart';

/// Открытые наборы — списком (`docs/spec/panel-sessions.md`, §3).
///
/// Свёрстано как окно адреса: поле сверху, список под ним, нечёткий отбор. Одно
/// отличие, и оно вынужденное: `Enter` показывает **выбранное в списке**, а не
/// открывает набранное. В адресном окне набранное и есть адрес, а набора,
/// которого нет, не открыть — поэтому поле здесь отбирает. То же и у окна
/// истории переходов, и по той же причине.
class SessionsDialogState extends ChangeNotifier {
  SessionsDialogState({required this.app, required this.side, required this.panels});

  final Application app;

  /// Куда показывать выбранное: сторона, из которой окно открыли.
  final ViewportPosition side;

  /// Снимок списка наборов на момент открытия.
  ///
  /// Снимком, а не живым списком: пока окно открыто, ввод у него, и заводить
  /// или закрывать наборы некому. Зато номера строк остаются теми же, что у
  /// `Alt-N`, и не прыгают под рукой.
  final List<Panel> panels;

  /// Закрыть окно; ставит команда, показавшая его.
  VoidCallback close = () {};

  String _query = '';

  String get query => _query;

  set query(String value) {
    if (_query == value) {
      return;
    }
    _query = value;
    // Отбор сузился — выбранное могло из него выпасть: ставим курсор на первое
    // оставшееся, а не оставляем его в пустоте.
    _selected = 0;
    notifyListeners();
  }

  int _selected = 0;

  int get selected => _selected;

  set selected(int value) {
    final found = shown;
    if (found.isEmpty) {
      return;
    }
    final next = value.clamp(0, found.length - 1);
    if (_selected == next) {
      return;
    }
    _selected = next;
    notifyListeners();
  }

  /// Строки всех наборов — порядком заведения.
  List<FcPickRow> get rows {
    final left = app.panelAt(ViewportPosition.left);
    final right = app.panelAt(ViewportPosition.right);

    return [
      for (var at = 0; at < panels.length; at++)
        FcPickRow(
          id: '$at',
          title: panelTitle(panels[at], panels),
          // Путь виден за именем: имена короткие и повторяются, а отличает
          // наборы именно место.
          subtitle: panels[at].session.currentPath,
          // И ищется — отдельно от имени: совпадение по имени всегда весомее,
          // иначе общее слово в пути выдавало бы половину списка вперёд
          // точного попадания.
          keywords: [panels[at].session.currentPath],
          // Номер — тот самый, что у `Alt-N`; дальше девятого номера нет и у
          // клавиши.
          leading: at < 9 ? '${at + 1}' : '',
          badge:
              identical(panels[at], left) || identical(panels[at], right)
                  ? FcSideMarks(
                    left: identical(panels[at], left),
                    right: identical(panels[at], right),
                    leftKey: SessionsDialogForm.leftMarkKey,
                    rightKey: SessionsDialogForm.rightMarkKey,
                  )
                  : null,
        ),
    ];
  }

  /// Что видно сейчас: отобранное набранным.
  ///
  /// Порядок при пустом запросе — заведения, а не алфавитный: номера `Alt-N` —
  /// это места в списке, и список обязан идти теми же номерами.
  List<FcPickRow> get shown =>
      FcPickList.filter(rows, _query, recent: [for (var at = 0; at < panels.length; at++) '$at']);

  /// Номер набора, показанного в этой стороне; -1 — такого нет.
  int get here {
    final panel = app.panelAt(side);
    for (var at = 0; at < panels.length; at++) {
      if (identical(panels[at], panel)) {
        return at;
      }
    }
    return -1;
  }

  /// Показать выбранное и закрыть окно.
  void submit() {
    final found = shown;
    if (found.isEmpty) {
      // Отбор ничего не нашёл — закрывать нечего и незачем: набранное осталось
      // бы потерянным.
      return;
    }
    tap(found[_selected.clamp(0, found.length - 1)].id);
  }

  /// Показать набор по номеру строки.
  void tap(String id) {
    final at = int.tryParse(id) ?? -1;
    if (at < 0 || at >= panels.length) {
      return;
    }
    close();
    app.showPanel(side, panels[at]);
  }
}

/// Поле отбора и список наборов.
class SessionsDialogForm extends StatefulWidget {
  const SessionsDialogForm({super.key, required this.state});

  /// Ключи горящих ячеек мини-пары — свои, не те же, что у ряда: общий ключ
  /// сделал бы находку двусмысленной, когда открыты оба.
  static const Key leftMarkKey = Key('sessions-dialog-mark-left');
  static const Key rightMarkKey = Key('sessions-dialog-mark-right');

  final SessionsDialogState state;

  @override
  State<SessionsDialogForm> createState() => _SessionsDialogFormState();
}

class _SessionsDialogFormState extends State<SessionsDialogForm> {
  final TextEditingController _query = TextEditingController();
  final FcPickPage _page = FcPickPage();

  @override
  void initState() {
    super.initState();
    // Курсор — на наборе, показанном здесь: чаще всего уходят отсюда, и видно,
    // откуда. Соседи при этом на виду сверху и снизу.
    final here = widget.state.here;
    if (here >= 0) {
      widget.state.selected = widget.state.shown.indexWhere((row) => row.id == '$here');
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final state = widget.state;
    final moved = FcPickList.moveSelection(
      event,
      selected: state.selected,
      count: state.shown.length,
      // Из списка не выйти: поле здесь отбирает, и возвращать в него нечего.
      wrap: false,
      page: _page,
    );
    if (moved == null) {
      // Иначе `Esc` и `Enter` не дойдут до рамы окна.
      return KeyEventResult.ignored;
    }
    state.selected = moved;
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final state = widget.state;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return SizedBox(
          // Доля экрана, как у палитры: в строке путь целиком, и от длины путей
          // окно прыгало бы на каждом открытии.
          width: MediaQuery.sizeOf(context).width * theme.metrics.paletteWidthFactor,
          child: Focus(
            onKeyEvent: _onKey,
            child: CommandDialogForm(
              onCancel: state.close,
              onSubmit: state.submit,
              submitLabel: context.strings.tr('Show'),
              children: [
                CommandDialogField.wide(
                  child: FcTextField(
                    controller: _query,
                    autofocus: true,
                    hintText: context.strings.tr('Filter by name or path'),
                    onChanged: (value) => state.query = value,
                    onSubmitted: (_) => state.submit(),
                  ),
                ),
                // Список до самых краёв окна: строка выбора обязана доходить до
                // них, иначе читается не как «эта строка», а как плитка.
                CommandDialogField.bleed(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (theme.metrics.rowHeight + theme.metrics.rowGap) * _visibleRows,
                    ),
                    child: FcPickList(
                      rows: state.shown,
                      query: state.query,
                      selected: state.selected,
                      page: _page,
                      emptyMessage: context.strings.tr('No session with such name or path'),
                      onTap: state.tap,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Сколько наборов видно разом; дальше список прокручивается.
  static const int _visibleRows = 12;
}
