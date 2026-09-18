import 'package:fc_api/fc_api.dart';
import 'dart:async';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'find_files_state.dart';

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
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (state.canGoTo) {
      if (event.logicalKey == LogicalKeyboardKey.f3) {
        unawaited(state.open(_viewCommand));
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.f4) {
        unawaited(state.open(_editCommand));
        return KeyEventResult.handled;
      }
    }

    // Курсор ведёт **сессия**: список один на окно и панель, и второго курсора
    // у него быть не может. Окно только переводит нажатие в шаг — привязки
    // команд до него не доходят, пока оно открыто (`screens.md`).
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        state.moveCursor(1);
      case LogicalKeyboardKey.arrowUp:
        state.moveCursor(-1);
      case LogicalKeyboardKey.pageDown:
        state.moveCursorPage(1);
      case LogicalKeyboardKey.pageUp:
        state.moveCursorPage(-1);
      case LogicalKeyboardKey.home:
        state.cursorToFirst();
      case LogicalKeyboardKey.end:
        state.cursorToLast();
      default:
        return KeyEventResult.ignored;
    }
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

    // Слушаем и состояние окна, и сессию: находки считает первое, а курсор по
    // ним ведёт вторая — и кнопки зависят от обоих.
    final session = state.results;
    return ListenableBuilder(
      listenable: session == null ? state : Listenable.merge([state, session]),
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
                FcButton(label: context.strings.tr('Close'), onPressed: state.finish),
                FcButton(label: context.strings.tr('Again'), onPressed: state.again),
                FcButton(label: context.strings.tr('Background'), onPressed: state.busy ? state.toBackground : null),
                FcButton(
                  label: context.strings.tr('View · F3'),
                  onPressed: state.canGoTo ? () => unawaited(state.open(_viewCommand)) : null,
                ),
                FcButton(
                  label: context.strings.tr('Edit · F4'),
                  onPressed: state.canGoTo ? () => unawaited(state.open(_editCommand)) : null,
                ),
                FcButton(
                  label: context.strings.tr('Go to file'),
                  onPressed: state.canGoTo ? () => unawaited(state.goTo()) : null,
                ),
                FcButton(
                  label: context.strings.tr('To panel'),
                  primary: true,
                  onPressed: state.tab == null ? null : () => unawaited(state.toPanel()),
                ),
              ],
              children: [
                CommandDialogField.wide(
                  // Растянули окно — прибавка достаётся списку: ради неё его и
                  // тянут. Сводка под ним остаётся на месте.
                  expands: true,
                  child: SizedBox(height: _visibleRows * theme.metrics.rowHeight, child: _list(context, state)),
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
                  children: [
                    _line(theme, context.strings.tr('Found: {count}', args: {'count': state.foundCount})),
                    _line(theme, _progress(context.strings, state)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Список находок — **та же сессия**, что показывает панель, и тем же видом.
  ///
  /// Не своя таблица: два устройства одного списка однажды расходятся, и
  /// разошлись (`docs/spec/file-search.md`, §3.2). Вид берётся из реестра, а не
  /// у модуля панелей: окно про его устройство не знает и знать не должно.
  Widget _list(BuildContext context, FindFilesState state) {
    final session = state.results;
    if (session == null) {
      return const SizedBox.shrink();
    }
    if (!state.busy && state.foundCount == 0 && state.searched) {
      // Словами, а не пустотой: «ничего не нашлось» — это ответ, и человек
      // должен отличать его от «ещё идёт».
      return Center(child: Text(context.strings.tr('Nothing found'), style: FcTheme.of(context).dialogLabelStyle));
    }
    final views = state.app.panelViews;
    final spec = views.byId(session.view) ?? views.available.firstOrNull;
    return spec == null ? const SizedBox.shrink() : spec.build(context, session);
  }

  /// Строка статистики постоянной высоты: у пустого текста нет ни одного глифа,
  /// и без этого он на пару точек ниже.
  Widget _line(FcTheme theme, String text) {
    final shown = Text(
      text,
      style: theme.dialogLabelStyle,
      strutStyle: StrutStyle.fromTextStyle(theme.dialogLabelStyle, forceStrutHeight: true),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    // Не `FcTrimmedText`: стойка постоянной высоты здесь важнее общей обёртки —
    // без неё строка прыгает на пару точек. Правило подсказки при этом общее.
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = FcTheme.effective(context, theme.dialogLabelStyle);
        final scaler = MediaQuery.textScalerOf(context);
        return fcTooltipIf(
          context,
          trimmed: !textFits(text, style, constraints.maxWidth, scaler),
          message: text,
          child: shown,
        );
      },
    );
  }

  /// Ход работы: где обход сейчас, а по окончании — чем он кончился.
  String _progress(Strings strings, FindFilesState state) {
    if (state.busy) {
      return state.at.isEmpty ? strings.tr('Searching…') : strings.tr('Searching {where}', args: {'where': state.at});
    }
    return state.stopped ? strings.tr('Stopped') : strings.tr('Done');
  }
}
