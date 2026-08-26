import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_dialog.dart';
import 'fc_theme.dart';

/// Строка таблицы: название и одно или два значения.
///
/// Третья ячейка нужна там, где значению нужно пояснение — команде, например,
/// нужны и клавиши, и описание. Где её нет, пустой столбец не остаётся:
/// у раздела столько столбцов, сколько ему нужно.
class FcTableRow {
  const FcTableRow(this.name, this.value, [this.note = '']);

  final String name;
  final String value;
  final String note;

  List<String> get cells => note.isEmpty ? [name, value] : [name, value, note];
}

/// Раздел таблицы — заголовок и строки под ним.
class FcTableSection {
  const FcTableSection(this.title, this.rows);

  final String title;
  final List<FcTableRow> rows;

  /// Сколько столбцов нужно разделу: по самой полной строке.
  int get columns => rows.fold(1, (count, row) => row.cells.length > count ? row.cells.length : count);
}

/// Таблица «ключ → значение» в окне команды: разделы, строки и одна кнопка.
///
/// Ею показывают справку, настройки, свойства объекта — всё, что укладывается
/// в пары «название — значение». Прокручивается сама: стрелками, PgUp/PgDn,
/// Home/End, — а Enter и Esc отдаёт раме окна.
///
/// Размер задаёт себе само: не больше окна приложения с полями по
/// [FcMetrics.dialogScreenInset] от каждого края. Рамка окна ширину не
/// назначает — она облегает то, что ей дали, — а высоту не ограничивает вовсе,
/// поэтому длинная таблица без этого вылезла бы за экран.
class FcKeyValueTable extends StatefulWidget {
  const FcKeyValueTable({super.key, required this.sections, required this.onClose, this.actions = const []});

  final List<FcTableSection> sections;
  final VoidCallback onClose;

  /// Кнопки левее «Close»: у справки их нет, у окна ошибки — «Report».
  ///
  /// Ряд кнопок собирается здесь, а не у вызывающего: он один на все окна
  /// приложения, и обходить его своей разметкой нельзя (см. ниже).
  final List<Widget> actions;

  @override
  State<FcKeyValueTable> createState() => _FcKeyValueTableState();
}

class _FcKeyValueTableState extends State<FcKeyValueTable> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Таблицу листают клавишами: справку читают, а не заполняют.
  ///
  /// Enter и Esc сюда не попадают — они не наши; их обработает рама окна, когда
  /// событие поднимется к ней.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }

    final position = _scroll.position;
    final step = FcTheme.of(context).metrics.rowHeight;
    final target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => position.pixels + step,
      LogicalKeyboardKey.arrowUp => position.pixels - step,
      LogicalKeyboardKey.pageDown => position.pixels + position.viewportDimension,
      LogicalKeyboardKey.pageUp => position.pixels - position.viewportDimension,
      LogicalKeyboardKey.home => position.minScrollExtent,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
    if (target == null) {
      return KeyEventResult.ignored;
    }

    _scroll.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return ConstrainedBox(
      // Не `SizedBox`: ширину окну задаёт содержимое, а это только предел.
      // Рама измеряет содержимое (`IntrinsicWidth`) и облегает его, поэтому
      // короткая таблица даёт узкое окно, а длинная упирается в поля.
      constraints: dialogContentLimits(context),
      child: SizedBox(
        // Ширина берётся у самого широкого раздела: строки внутри растягиваются
        // на всё, что им дали, и сами по себе ничего не требуют.
        width: double.infinity,
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: dialogContentPadding(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < widget.sections.length; i++) ...[
                        if (i > 0) SizedBox(height: metrics.dialogGap),
                        _SectionTable(section: widget.sections[i]),
                      ],
                    ],
                  ),
                ),
              ),
              // Тот же ряд, что и у остальных окон: кнопка по размеру подписи,
              // прижата вправо. Своей разметкой её обходить нельзя — `FcButton`
              // под ограниченной шириной растягивается во всю её ширину.
              CommandDialogActions(
                actions: [...widget.actions, FcButton(label: 'Close', onPressed: widget.onClose, primary: true)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Раздел справки таблицей: столбцы по своему содержимому.
///
/// У каждого раздела таблица своя, потому что и столбцы у них разные: в
/// настройках их два, в списке команд — три. Ширина столбца — по самой длинной
/// строке в нём (`IntrinsicColumnWidth`), поэтому окно получается ровно таким,
/// каким его делает содержимое.
///
/// Ячейка при этом не растёт бесконечно: длинный путь или описание упираются в
/// [FcMetrics.helpCellMaxWidth] и переносятся по строкам. Без этого одна
/// длинная строка растянула бы окно до полей экрана, а таблица с
/// `IntrinsicColumnWidth` под тесной разметкой не ужимается, а вылезает наружу.
class _SectionTable extends StatelessWidget {
  const _SectionTable({required this.section});

  final FcTableSection section;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final columns = section.columns;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: metrics.dialogPadding / 2),
          child: Text(section.title, style: theme.dialogTitleStyle),
        ),
        Table(
          columnWidths: {for (var i = 0; i < columns; i++) i: const IntrinsicColumnWidth()},
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            for (final row in section.rows)
              TableRow(
                children: [
                  for (var i = 0; i < columns; i++)
                    Padding(
                      // Последний столбец без правого поля: за ним край окна.
                      padding: EdgeInsets.only(
                        right: i == columns - 1 ? 0 : metrics.dialogGap,
                        bottom: metrics.dialogPadding / 4,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: metrics.helpCellMaxWidth),
                        child: Text(
                          i < row.cells.length ? row.cells[i] : '',
                          style: i == 0 ? theme.dialogLabelStyle : theme.dialogTextStyle,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
