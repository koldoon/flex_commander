import 'dart:async';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'find_files_state.dart';
import 'found_table.dart';

/// Окно находок — вторая фаза поиска.
///
/// Полей ввода здесь нет вовсе: спрашивали в первом окне, здесь показывают, что
/// нашлось. Так устроен `mc`, и разделение не косметическое — находкам нужно
/// всё окно, а параметры к этому времени уже не нужны никому.
///
/// Внизу, как в `mc`, статистика и кнопки: сколько нашлось и где обход сейчас.
class FindFilesResults extends StatefulWidget {
  const FindFilesResults({super.key, required this.state});

  final FindFilesState state;

  @override
  State<FindFilesResults> createState() => _FindFilesResultsState();
}

class _FindFilesResultsState extends State<FindFilesResults> {
  final FocusNode _focus = FocusNode(debugLabel: 'find files results');

  /// Размер страницы для `PgUp`/`PgDn`: список кладёт его сюда.
  final FcPickPage _page = FcPickPage();

  /// Сколько строк находок видно. Больше — и окно упрётся в край экрана;
  /// меньше — и список перестанет быть списком.
  static const int _visibleRows = 16;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Стрелки водят по находкам, `F3` и `F4` открывают выбранную.
  ///
  /// Клавиши ловит окно, а не реестр команд: пока окно открыто, клавиши
  /// принадлежат ему целиком (`screens.md`), и до привязок они не доходят.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final state = widget.state;
    if (event is KeyDownEvent && state.canGoTo) {
      if (event.logicalKey == LogicalKeyboardKey.f3) {
        unawaited(state.open(_viewCommand));
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.f4) {
        unawaited(state.open(_editCommand));
        return KeyEventResult.handled;
      }
    }

    final moved = FcPickList.moveSelection(
      event,
      selected: state.selected,
      count: state.found.length,
      wrap: false,
      page: _page,
    );
    if (moved == null) {
      return KeyEventResult.ignored;
    }
    state.select(moved);
    return KeyEventResult.handled;
  }

  /// Те же команды, что за `F3` и `F4` в панели: открывать файл в приложении
  /// умеют они, и второго такого умения заводить не надо.
  static const String _viewCommand = 'file.view';
  static const String _editCommand = 'file.edit';

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final state = widget.state;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return SizedBox(
          // Ширина — доля экрана: пути находок бывают длинными и разными, и от
          // них окно прыгало бы на каждой пачке. Шире, чем у окна параметров:
          // здесь список, и ему нужна строка.
          width: MediaQuery.sizeOf(context).width * theme.metrics.paletteWidthFactor,
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: CommandDialogBody(
              actions: [
                FcButton(label: 'Close', onPressed: state.finish),
                FcButton(label: 'Again', onPressed: state.again),
                FcButton(label: 'Background', onPressed: state.busy ? state.toBackground : null),
                FcButton(
                  label: 'View · F3',
                  onPressed: state.canGoTo ? () => unawaited(state.open(_viewCommand)) : null,
                ),
                FcButton(
                  label: 'Edit · F4',
                  onPressed: state.canGoTo ? () => unawaited(state.open(_editCommand)) : null,
                ),
                FcButton(label: 'Go to file', onPressed: state.canGoTo ? () => unawaited(state.goTo()) : null),
                FcButton(
                  label: 'To panel',
                  primary: true,
                  onPressed: state.found.isEmpty ? null : () => unawaited(state.toPanel()),
                ),
              ],
              children: [
                CommandDialogField.wide(
                  child: FoundTable(
                    rows: state.rows,
                    selected: state.selected,
                    rowOfFound: state.rowOfFound,
                    visibleRows: _visibleRows,
                    page: _page,
                    emptyMessage: state.busy ? '' : 'Nothing found',
                    onTap: state.select,
                  ),
                ),
                // Две строки, как в `mc`: сколько нашлось и где обход сейчас.
                // Обе стоят всегда — строка, то появляющаяся, то исчезающая,
                // двигала бы список под курсором ровно тогда, когда в него
                // смотрят.
                //
                // Одной строкой формы из двух строк, а не двумя строками: это
                // одна сводка о поиске, и отбивать её половины друг от друга
                // так же, как от списка, значило бы читать их как разное.
                CommandDialogField.column(
                  label: '',
                  children: [_line(theme, 'Found: ${state.found.length}'), _line(theme, _progress(state))],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Строка статистики постоянной высоты: у пустого текста нет ни одного глифа,
  /// и без этого он на пару точек ниже.
  Widget _line(FcTheme theme, String text) => Text(
    text,
    style: theme.dialogLabelStyle,
    strutStyle: StrutStyle.fromTextStyle(theme.dialogLabelStyle, forceStrutHeight: true),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  /// Ход работы: где обход сейчас, а по окончании — чем он кончился.
  String _progress(FindFilesState state) {
    if (state.busy) {
      return state.at.isEmpty ? 'Searching…' : 'Searching ${state.at}';
    }
    return state.stopped ? 'Stopped' : 'Done';
  }
}
