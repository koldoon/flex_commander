import 'dart:async';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'find_files_state.dart';
import 'found_table.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final state = widget.state;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        // Ширина — доля экрана, а не размер содержимого: пути находок бывают
        // длинными и разными, и от них окно прыгало бы на каждой пачке. Тем же
        // ответом снимается вопрос рамы о ширине — а ленивая таблица находок
        // отвечать на него и не умеет.
        return SizedBox(
          width: MediaQuery.sizeOf(context).width * theme.metrics.dialogWidthFactor,
          child: CommandDialogBody(
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
              // Ход работы и итог — на одном и том же месте, и место это занято
              // **всегда**: пока идёт обход, здесь виден каталог, в котором он
              // сейчас; кончился — сколько нашлось; до первого поиска пусто.
              //
              // Строка, то появляющаяся, то исчезающая, двигала бы таблицу под
              // курсором ровно в тот миг, когда в неё смотрят. Дырой пустая
              // строка не выглядит: под ней стоит рамка таблицы, и видно, что
              // место занято делом.
              CommandDialogField.wide(
                child: Text(
                  _summary(state),
                  style: theme.dialogLabelStyle,
                  // Высота строки постоянная, что бы в ней ни стояло: у пустого
                  // текста нет ни одного глифа, и без этого он на пару точек
                  // ниже — а на эти пару точек ездила бы таблица под ним.
                  strutStyle: StrutStyle.fromTextStyle(theme.dialogLabelStyle, forceStrutHeight: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Таблица стоит **всегда**, и размер у неё постоянный: пустая
              // рамка читается как «сюда придут находки», а список, растущий по
              // ходу работы, дёргал бы окно под курсором на каждой пачке.
              CommandDialogField.wide(
                child: FoundTable(
                  nodes: state.found,
                  selected: state.selected,
                  whereOf: state.whereOf,
                  rows: _visibleRows,
                  page: _page,
                  emptyMessage: state.searched ? 'Nothing found' : '',
                  onTap: (index) {
                    state.select(index);
                    unawaited(state.goTo());
                  },
                ),
              ),
            ],
          ),
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
      // Про «ничего не нашлось» говорит сама таблица — своей пустотой и
      // словами в ней. Повторять это второй строкой незачем.
      return '';
    }
    return 'Found $count ${count == 1 ? 'item' : 'items'}';
  }
}
