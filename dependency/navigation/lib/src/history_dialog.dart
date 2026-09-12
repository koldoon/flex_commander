import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Пройденное этой сессией — списком (`docs/spec/session-history.md`, §9).
///
/// Свёрстано как окно адреса: поле сверху, список под ним, нечёткий отбор.
/// Одно отличие, и оно вынужденное: `Enter` переходит на **выбранное в
/// списке**, а не открывает набранное. В адресном окне набранное и есть адрес,
/// а шага, которого в истории нет, не открыть — поэтому поле здесь отбирает.
class HistoryDialogState extends ChangeNotifier {
  HistoryDialogState({required this.panel, required this.steps, required this.current});

  final Session panel;

  /// Шаги от старого к новому — тем же порядком, каким их помнит сессия.
  final List<PathStep> steps;

  /// Номер шага, на котором сессия стоит сейчас; −1 — истории нет.
  final int current;

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

  /// Строки списка в том порядке, в каком их видно: свежие сверху.
  ///
  /// Сверху свежее — так же, как в истории адресов: последнее место ближе к
  /// руке, а «назад» ведёт вниз по списку.
  List<FcPickRow> get rows => [
    for (var i = steps.length - 1; i >= 0; i--)
      FcPickRow(
        // Номер шага, а не путь: одно и то же место в истории встречается
        // дважды, и вернуться надо именно на выбранный шаг.
        id: '$i',
        title: steps[i].path,
        marked: i == current,
      ),
  ];

  /// Отобранное набранным — тем же нечётким правилом, что в палитре.
  ///
  /// Порядок свежести объявляется отдельно ([recent]): при пустом запросе вес
  /// у всех строк одинаковый, и без этого список разложился бы по алфавиту —
  /// а история читается по времени, а не по азбуке.
  List<FcPickRow> get shown => FcPickList.filter(rows, _query, recent: _fresh);

  /// Номера шагов от свежего к старому.
  List<String> get _fresh => [for (var i = steps.length - 1; i >= 0; i--) '$i'];

  /// Открыть выбранный шаг. Пусто в списке — закрывать нечего, и окно стоит.
  Future<void> submit() async {
    final found = shown;
    if (found.isEmpty) {
      return;
    }
    final at = int.tryParse(found[_selected.clamp(0, found.length - 1)].id);
    close();
    if (at != null) {
      await panel.goToStep(at);
    }
  }

  /// Перейти на шаг, выбранный мышью: щелчок — то же, что выбрать и нажать
  /// `Enter`, а не «просто выбрать». Список короткий, и вторым нажатием здесь
  /// ничего не уточняют.
  Future<void> tap(String id) async {
    final at = int.tryParse(id);
    close();
    if (at != null) {
      await panel.goToStep(at);
    }
  }
}

/// Содержимое окна: поле отбора и список пройденного.
class HistoryDialogForm extends StatefulWidget {
  const HistoryDialogForm({super.key, required this.state});

  final HistoryDialogState state;

  @override
  State<HistoryDialogForm> createState() => _HistoryDialogFormState();
}

class _HistoryDialogFormState extends State<HistoryDialogForm> {
  final TextEditingController _query = TextEditingController();
  final FcPickPage _page = FcPickPage();

  @override
  void initState() {
    super.initState();
    // Курсор встаёт на том шаге, где сессия стоит сейчас: от него человек и
    // считает, куда ему надо — на два назад или на один вперёд.
    final state = widget.state;
    final rows = state.rows;
    final at = rows.indexWhere((row) => row.marked);
    if (at >= 0) {
      state.selected = at;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Стрелки водят по списку, минуя поле: в поле набирают, а ходят по списку.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final state = widget.state;
    final moved = FcPickList.moveSelection(
      event,
      selected: state.selected,
      count: state.shown.length,
      wrap: false,
      page: _page,
    );
    if (moved == null) {
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
          // Доля экрана, как у палитры: в строке путь целиком, и от длины
          // путей окно прыгало бы на каждом шаге.
          width: MediaQuery.sizeOf(context).width * theme.metrics.paletteWidthFactor,
          child: Focus(
            onKeyEvent: _onKey,
            child: CommandDialogForm(
              onCancel: state.close,
              onSubmit: () => unawaited(state.submit()),
              submitLabel: context.strings.tr('Go'),
              children: [
                CommandDialogField.wide(
                  child: FcTextField(
                    controller: _query,
                    autofocus: true,
                    hintText: context.strings.tr('Filter by path'),
                    onChanged: (value) => state.query = value,
                    onSubmitted: (_) => unawaited(state.submit()),
                  ),
                ),
                // Список до самых краёв окна: строка выбора обязана доходить
                // до них, иначе читается не как «эта строка», а как плитка.
                CommandDialogField.bleed(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (theme.metrics.rowHeight + theme.metrics.rowGap) * _visibleRows,
                    ),
                    child: FcPickList(
                      trimHead: true,
                      // Ярко — последнее звено пути: именно им строки и
                      // различаются, начало у соседних чаще всего одно.
                      dimPathHead: true,
                      // Пути режутся с головы, как в плашке: конец важнее —
                      // в нём тот каталог, о котором речь.
                      rows: state.shown,
                      query: state.query,
                      selected: state.selected,
                      page: _page,
                      emptyMessage: context.strings.tr('Nothing found'),
                      onTap: (id) => unawaited(state.tap(id)),
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

  /// Сколько шагов видно разом; дальше список прокручивается.
  static const int _visibleRows = 12;
}
