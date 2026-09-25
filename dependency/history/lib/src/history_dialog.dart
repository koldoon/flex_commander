import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'undo_plan.dart';

/// Что приложение сделало за сеанс — списком
/// (`docs/spec/operation-history.md`, §10).
///
/// Свёрстано как окно пройденных путей: поле отбора сверху, список под ним.
/// Отменяется **только верхняя** запись: перескок через неё возвращал бы мир,
/// которого уже нет, — и об этом окно говорит прямо.
class HistoryDialogState extends ChangeNotifier {
  HistoryDialogState({required this.history, required this.strings, required this.undo});

  final OperationHistory history;
  final Strings strings;

  /// Чем отменить верхнюю запись; зовётся по `Enter` и по щелчку.
  final Future<void> Function() undo;

  /// Закрыть окно; ставит команда, показавшая его.
  VoidCallback close = () {};

  /// Что сказать о невозможности — показывается вместо перечня.
  String? notice;

  String _query = '';

  String get query => _query;

  set query(String value) {
    if (_query == value) {
      return;
    }
    _query = value;
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

  /// Строки: работа, что она сделала и когда.
  List<FcPickRow> get rows => [
    for (final (at, record) in history.all.indexed)
      FcPickRow(
        // Номером, а не именем работы: одинаковых работ за сеанс сколько
        // угодно, а вернуться надо к этой.
        id: '$at',
        title: titleOfKind(record.kind, strings),
        subtitle: _saidAbout(record),
        // Помечена та, которую и отменят: не всегда верхняя — сама отмена и
        // уже отменённое пропускаются (§9).
        marked: record.runId == history.undoTarget?.runId,
      ),
  ];

  List<FcPickRow> get shown =>
      FcPickList.filter(rows, _query, recent: [for (final (at, _) in history.all.indexed) '$at']);

  /// Что строка говорит о себе: сколько объектов, когда и почему неотменима.
  String _saidAbout(HistoryRecord record) {
    final when = '${_two(record.at.hour)}:${_two(record.at.minute)}';
    if (record.isRunning) {
      return '$when · ${strings.tr('still running')}';
    }
    final counted = strings.plural(record.count, one: '{n} object', other: '{n} objects');
    final said = record.undone ? strings.tr('undone') : (record.obstacle == null ? null : strings.tr(record.obstacle!));
    return said == null ? '$when · $counted' : '$when · $counted · $said';
  }

  static String _two(int value) => value < 10 ? '0$value' : '$value';

  /// Отменить: только верхнюю. Выбранная ниже — не ошибка человека, а вопрос,
  /// на который надо ответить словами.
  Future<void> submit() async {
    final found = shown;
    if (found.isEmpty) {
      return;
    }
    final at = int.tryParse(found[_selected.clamp(0, found.length - 1)].id);
    final chosen = at == null || at >= history.all.length ? null : history.all[at];
    if (chosen == null || chosen.runId != history.undoTarget?.runId) {
      // Перескок вернул бы мир, которого уже нет (§11).
      notice = strings.tr('Only the newest operation can be undone');
      notifyListeners();
      return;
    }
    close();
    await undo();
  }

  Future<void> tap(String id) async {
    selected = shown.indexWhere((row) => row.id == id);
    await submit();
  }
}

/// Содержимое окна: поле отбора и список работ.
class HistoryDialogForm extends StatefulWidget {
  const HistoryDialogForm({super.key, required this.state});

  final HistoryDialogState state;

  @override
  State<HistoryDialogForm> createState() => _HistoryDialogFormState();
}

class _HistoryDialogFormState extends State<HistoryDialogForm> {
  /// Сколько работ видно разом; дальше список прокручивается.
  static const int _visibleRows = 12;

  final TextEditingController _query = TextEditingController();
  final FcPickPage _page = FcPickPage();

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
    // Высоту окну задала рама — значит, её кто-то должен занять, и занимает
    // список: он здесь главное.
    final stretches = FcDialogSizing.of(context);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return SizedBox(
          // Доля экрана, как у палитры: в строке путь и счёт объектов, и от
          // их длины окно прыгало бы на каждой работе.
          width: MediaQuery.sizeOf(context).width * theme.metrics.paletteWidthFactor,
          child: Focus(
            onKeyEvent: _onKey,
            child: CommandDialogForm(
              onCancel: state.close,
              onSubmit: () => unawaited(state.submit()),
              submitLabel: context.strings.tr('Undo'),
              children: [
                CommandDialogField.wide(
                  child: FcTextField(
                    controller: _query,
                    autofocus: true,
                    hintText: context.strings.tr('Filter operations'),
                    onChanged: (value) => state.query = value,
                    onSubmitted: (_) => unawaited(state.submit()),
                  ),
                ),
                // Отказ — строкой над списком: окно остаётся открытым, а
                // сказать, почему нажатие ничего не сделало, надо здесь же.
                if (state.notice case final said?) CommandDialogField.wide(child: FcErrorText(message: said)),
                CommandDialogField.bleed(
                  // Растянули окно — прибавка достаётся списку; не растягивали
                  // — он назначает высоту себе сам. Ленивый список себя мерить
                  // не умеет, а рама окна, которому высоту задали, не
                  // подвинется под его желания (`docs/spec/dialog-resize.md`,
                  // §6).
                  expands: true,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          stretches ? double.infinity : (theme.metrics.rowHeight + theme.metrics.rowGap) * _visibleRows,
                    ),
                    child: FcPickList(
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
}

/// Как работа называется в списке.
///
/// Имена родов — машинные (`file.copy`), и показывать их человеку нельзя;
/// перевода у них тоже нет — переводится **название**, а оно уже есть у команд,
/// которые эти работы заводят. Чужого рода здесь не бывает, но если появится —
/// покажем как есть, это честнее пустой строки.
String titleOfKind(String kind, Strings strings) => switch (kind) {
  'file.copy' => strings.tr('Copy'),
  'file.move' => strings.tr('Move'),
  'file.remove' => strings.tr('Delete'),
  'file.makeDirectory' => strings.tr('Make directory'),
  'file.rename' => strings.tr('Rename'),
  'file.renameBatch' => strings.tr('Multi-rename'),
  'history.undo' => strings.tr('Undo'),
  _ => kind,
};

/// Что окно скажет о верхней записи, если отменить её нельзя.
String describeUndo(OperationHistory history, Strings strings) {
  final record = history.last;
  if (record == null) {
    return strings.tr('Nothing to undo');
  }
  return UndoPlan.of(record.journal).describe(strings);
}
