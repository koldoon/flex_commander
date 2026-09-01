import 'dart:async';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'find_files_state.dart';

/// Окно поиска: маска, флаги, ход работы и то, что нашлось.
class FindFilesForm extends StatefulWidget {
  const FindFilesForm({super.key, required this.state});

  final FindFilesState state;

  @override
  State<FindFilesForm> createState() => _FindFilesFormState();
}

class _FindFilesFormState extends State<FindFilesForm> {
  final TextEditingController _mask = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'find files mask');

  /// Размер страницы для `PgUp`/`PgDn`: список меряет обзор и кладёт его сюда.
  final FcPickPage _page = FcPickPage();

  /// Сколько строк находок показывать: дальше окно росло бы вслед за деревом.
  static const int _visibleRows = 8;

  @override
  void initState() {
    super.initState();
    _mask.text = widget.state.query.mask;
  }

  @override
  void dispose() {
    _mask.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Стрелки водят по находкам, не уводя набор из поля маски.
  ///
  /// Так же, как в окне пометки: поле держит ввод, а список — выбор, и
  /// переключаться между ними табуляцией ради одной стрелки незачем.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final state = widget.state;
    final moved = FcPickList.moveSelection(
      event,
      selected: state.selected,
      // По показанному, а не по всему найденному: за строкой, которой нет на
      // экране, курсор ушёл бы в никуда.
      count: state.shown.length,
      wrap: false,
      page: _page,
    );
    if (moved == null) {
      return KeyEventResult.ignored;
    }
    state.select(moved);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final state = widget.state;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return CommandDialogBody(
          // Кнопки идут слева направо к главной, а главная меняется вместе с
          // делом: пока не искали — это «Begin», как только нашлось — «To
          // panel». Обе кнопки про находки до первого поиска не показываются
          // вовсе: мёртвая кнопка, у которой ещё и смысл неочевиден, — это
          // вопрос без ответа.
          actions: [
            // Пока идёт обход, «Закрыть» становится «Стоп»: прекратить нужнее,
            // чем уйти, а найденное при этом остаётся на месте.
            FcButton(label: state.busy ? 'Stop' : 'Close', onPressed: state.busy ? state.stop : state.close),
            FcButton(
              label: 'Begin',
              primary: state.found.isEmpty,
              onPressed: state.canStart ? () => unawaited(state.start()) : null,
            ),
            if (state.found.isNotEmpty) ...[
              // «К файлу», а не просто «перейти»: рядом стоит «весь список в
              // панель», и по одному имени их было не различить.
              FcButton(label: 'Go to file', onPressed: state.canGoTo ? () => unawaited(state.goTo()) : null),
              FcButton(label: 'To panel', primary: true, onPressed: () => unawaited(state.toPanel())),
            ],
          ],
          children: [
            CommandDialogField(
              label: 'Mask',
              child: Focus(
                focusNode: _focus,
                onKeyEvent: _onKey,
                // `Enter` полю не отдаётся: в открытом окне его разбирает рама
                // и отдаёт окну (`DialogSpec.onSubmit`). Два пути к одному
                // действию разошлись бы в первый же день, когда одному из них
                // добавят условие.
                child: FcTextField(
                  controller: _mask,
                  autofocus: true,
                  hintText: '*.dart;!*.g.dart',
                  onChanged: state.typed,
                ),
              ),
            ),
            // Где ищем — показано, но не правится: чтобы искать в другом месте,
            // туда переходят панелью.
            CommandDialogField(
              label: 'In',
              child: Text(state.where.pathString, style: theme.dialogTextStyle, overflow: TextOverflow.ellipsis),
            ),
            CommandDialogField.wide(
              child: FcCheckbox(
                label: 'Look inside subdirectories',
                value: state.query.recursive,
                onChanged: state.busy ? null : state.setRecursive,
              ),
            ),
            CommandDialogField.wide(
              child: FcCheckbox(
                label: 'Include hidden files',
                value: state.query.hidden,
                onChanged: state.busy ? null : state.setHidden,
              ),
            ),
            // Ход работы и итог — на одном и том же месте: пока идёт обход,
            // здесь виден каталог, в котором он сейчас; кончился — сколько
            // нашлось. Строки нет вовсе, пока сказать нечего: пустая занимала
            // место, и между формой и кнопками зияла дыра непонятно подо что.
            if (state.busy || state.searched)
              CommandDialogField.wide(
                child: Text(
                  _summary(state),
                  style: theme.dialogLabelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (state.found.isNotEmpty)
              CommandDialogField.bleed(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (theme.metrics.rowHeight + theme.metrics.rowGap) * _visibleRows,
                  ),
                  child: FcPickList(
                    rows: [
                      for (final node in state.shown)
                        FcPickRow(id: node.pathString, title: node.name, trailing: state.whereOf(node)),
                    ],
                    // Отбирать нечего: список и есть ответ на заданный вопрос,
                    // а подсвечивать в именах маску нельзя — она не подстрока.
                    query: '',
                    selected: state.selected,
                    page: _page,
                    onTap: (path) {
                      state.select(state.found.indexWhere((node) => node.pathString == path));
                      unawaited(state.goTo());
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Строка под полями: где идём или что нашли.
  ///
  /// До первого поиска — пусто. Здесь стояла подсказка «Press Enter to
  /// search», и она лишняя: `Enter` в окне значит «сделать» всегда и везде,
  /// и объяснять это в одном окне — значит намекать, что в остальных иначе.
  /// Место при этом остаётся занятым: строка та же, просто без текста, и окно
  /// не дёргается, когда ей есть что сказать.
  String _summary(FindFilesState state) {
    if (state.busy) {
      return state.at.isEmpty ? 'Searching…' : 'Searching ${state.at}';
    }
    if (!state.searched) {
      return '';
    }
    final count = state.found.length;
    if (count == 0) {
      return 'Nothing found';
    }
    final total = 'Found $count ${count == 1 ? 'item' : 'items'}';
    // Показано не всё — об этом говорят прямо: молча обрезанный список
    // заставил бы искать пропажу.
    return state.allShown ? total : '$total, first ${FindFilesState.shownLimit} shown';
  }
}
