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

/// Разделы «ключ → значение» — без рамы и без кнопок.
///
/// Отдельно от [FcKeyValueTable] потому, что мест у этой разметки два: окно
/// команды (там снизу кнопки) и область панели, где показывают сведения об
/// объекте (там кнопок нет вовсе). Разметка при этом обязана быть одна: два
/// показа одного и того же однажды разойдутся.
///
/// Прокручивается сама: стрелками, PgUp/PgDn, Home/End, — а Enter и Esc
/// отдаёт тому, кто её показывает.
class FcKeyValueSections extends StatefulWidget {
  const FcKeyValueSections({super.key, required this.sections, this.autofocus = true, this.padded = true});

  final List<FcTableSection> sections;

  /// Забирать ли фокус: в окне — да, листать её приходится сразу; в панели —
  /// нет, там ввод принадлежит списку файлов.
  final bool autofocus;

  /// Отступы содержимого окна. В панели у рамы свои.
  final bool padded;

  @override
  State<FcKeyValueSections> createState() => _FcKeyValueSectionsState();
}

class _FcKeyValueSectionsState extends State<FcKeyValueSections> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Таблицу листают клавишами: её читают, а не заполняют.
  ///
  /// Enter и Esc сюда не попадают — они не наши; их обработает рама, когда
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
      LogicalKeyboardKey.home => 0.0,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
    if (target == null) {
      return KeyEventResult.ignored;
    }
    _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    return KeyEventResult.handled;
  }

  /// Сколько столбцов нужно — по самому полному разделу.
  int get _columns => widget.sections.fold(1, (count, section) => section.columns > count ? section.columns : count);

  /// Ширины столбцов, кроме последнего, — **по всем разделам сразу**.
  ///
  /// Одна таблица, а не таблица на раздел: подписи разных разделов описывают
  /// один и тот же объект, и стоять они обязаны на одной глубине. Последний
  /// столбец здесь не меряется — ему достаётся весь остаток, и переносится он
  /// по краю окна, а не раньше.
  List<double> _widths(BuildContext context) {
    final theme = FcTheme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final widths = List<double>.filled(_columns, 0);

    for (final section in widget.sections) {
      for (final row in section.rows) {
        final cells = row.cells;
        for (var i = 0; i < cells.length && i < _columns - 1; i++) {
          final painter = TextPainter(
            text: TextSpan(text: cells[i], style: i == 0 ? theme.dialogLabelStyle : theme.dialogTextStyle),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width > theme.metrics.helpCellMaxWidth ? theme.metrics.helpCellMaxWidth : painter.width;
          if (width > widths[i]) {
            widths[i] = width;
          }
          painter.dispose();
        }
      }
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final widths = _widths(context);
    final columns = _columns;

    return Focus(
      autofocus: widget.autofocus,
      canRequestFocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: widget.padded ? dialogContentPadding(context) : EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.sections.length; i++) ...[
              if (i > 0) SizedBox(height: metrics.sectionGap),
              // Заголовок раздела — строкой во всю ширину: столбцы под ним те
              // же, что и у соседних разделов. И крупнее подписей, а не только
              // жирнее: разделов много, и на общем кегле заголовок теряется
              // среди них — то же решение, что в окне настроек.
              Padding(
                padding: EdgeInsets.only(bottom: metrics.sectionEntryGap),
                child: Text(
                  widget.sections[i].title,
                  style: theme.dialogTitleStyle.copyWith(fontSize: metrics.sectionHeadingFontSize),
                ),
              ),
              _rows(theme, widget.sections[i], widths, columns),
            ],
          ],
        ),
      ),
    );
  }

  /// Строки раздела — таблицей с **общими** ширинами столбцов.
  ///
  /// Таблица на раздел, а ширины общие: со стороны это и есть одна таблица, у
  /// которой заголовки разделов идут во всю ширину. Собственный `Row` с
  /// `Expanded` тут не годится — рама окна меряет содержимое (`IntrinsicWidth`),
  /// а `Expanded` в такой замер не укладывается и переполняет строку.
  Widget _rows(FcTheme theme, FcTableSection section, List<double> widths, int columns) {
    final metrics = theme.metrics;

    return Table(
      columnWidths: {
        for (var i = 0; i < columns - 1; i++) i: FixedColumnWidth(widths[i] + metrics.dialogGap),
        // Последний столбец меряется по себе **и** забирает остаток.
        //
        // Оба разом: по себе — чтобы окно выросло под длинное значение (рама
        // облегает содержимое, а `FlexColumnWidth` в замере отвечает нулём и
        // ширины окну не прибавляет); остаток — чтобы на широком окне значение
        // занимало всё место, а не половину.
        columns - 1: const IntrinsicColumnWidth(flex: 1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final row in section.rows)
          TableRow(
            children: [
              for (var i = 0; i < columns; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: metrics.dialogPadding / 4),
                  child: Text(
                    i < row.cells.length ? row.cells[i] : '',
                    style: i == 0 ? theme.dialogLabelStyle : theme.dialogTextStyle,
                  ),
                ),
            ],
          ),
      ],
    );
  }
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
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Не `SizedBox`: ширину окну задаёт содержимое, а это только предел.
      // Рама измеряет содержимое (`IntrinsicWidth`) и облегает его, поэтому
      // короткая таблица даёт узкое окно, а длинная упирается в поля.
      constraints: dialogContentLimits(context),
      child: SizedBox(
        // Ширина берётся у самого широкого раздела: строки внутри растягиваются
        // на всё, что им дали, и сами по себе ничего не требуют.
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(child: FcKeyValueSections(sections: widget.sections)),
            // Тот же ряд, что и у остальных окон: кнопка по размеру подписи,
            // прижата вправо. Своей разметкой её обходить нельзя — `FcButton`
            // под ограниченной шириной растягивается во всю её ширину.
            CommandDialogActions(
              actions: [...widget.actions, FcButton(label: 'Close', onPressed: widget.onClose, primary: true)],
            ),
          ],
        ),
      ),
    );
  }
}
