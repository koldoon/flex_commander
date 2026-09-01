import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'find_files_state.dart';

/// Находки в окне поиска: список каталогами, в рамке и **ленивый**.
///
/// Раскладка из `mc`: строка с путём каталога, под ней найденные в нём файлы с
/// отступом. Каталог называется один раз на пачку — обход идёт каталогами, и
/// находки из одного приходят подряд.
///
/// **Ленивость — условие этой раскладки, а не добавка к ней.** Находок бывают
/// тысячи, и строить их все на каждую перерисовку нельзя: на этом приложение и
/// вставало. Ленивый список умеет строить только видимое ровно тогда, когда
/// строки одной высоты, — поэтому список **плоский**, из строк двух видов
/// ([FoundRow]), а не дерево.
///
/// Общий список окон ([FcPickList]) так не умеет и не должен: он стоит в окне,
/// которое меряет содержимое (`IntrinsicWidth`), а ленивый список на вопрос о
/// собственной ширине не отвечает. Здесь этого вопроса нет — окно берёт ширину
/// долей экрана ([DialogSpec.ownWidth]), и мерить его содержимое некому.
///
/// **Курсор ходит по находкам, а не по строкам.** [selected] — номер находки;
/// заголовки он проходит насквозь, потому что они не файлы и делать с ними
/// нечего. Где выбранная находка нарисована, отвечает [rowOfFound] — и нужно
/// это только затем, чтобы подвести её под обзор.
class FoundTable extends StatefulWidget {
  const FoundTable({
    super.key,
    required this.rows,
    required this.selected,
    required this.rowOfFound,
    required this.onTap,
    required this.visibleRows,
    this.page,
    this.emptyMessage = '',
  });

  /// Что показывать. Строки собираются **по одной, по мере показа**.
  final List<FoundRow> rows;

  /// Находка под курсором; -1 — ни одной.
  final int selected;

  /// Какой строкой нарисована находка с этим номером.
  final int Function(int index) rowOfFound;

  /// Выбрали находку — её номер.
  final void Function(int index) onTap;

  /// Сколько строк видно: высота считается по ним и больше ни по чему.
  final int visibleRows;

  /// Куда положить размер страницы для `PgUp`/`PgDn`.
  final FcPickPage? page;

  /// Что сказать, пока показывать нечего.
  final String emptyMessage;

  @override
  State<FoundTable> createState() => _FoundTableState();
}

class _FoundTableState extends State<FoundTable> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(FoundTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      // После раскладки: до неё у прокрутки нет ни высоты, ни позиции.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSelected());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Высота строки — та же, что в списке файлов панели.
  double _line(FcMetrics metrics) => metrics.rowHeight + metrics.rowGap;

  /// Подводит выбранную находку под обзор.
  ///
  /// Считается по номеру **строки**, а не находки: между находками стоят
  /// заголовки каталогов, и без пересчёта прокрутка уезжала бы тем сильнее, чем
  /// больше каталогов позади.
  void _showSelected() {
    final row = widget.rowOfFound(widget.selected);
    if (!_scroll.hasClients || row < 0) {
      return;
    }
    final line = _line(FcTheme.of(context).metrics);
    final top = row * line;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + line > position.pixels + position.viewportDimension) {
      _scroll.jumpTo((top + line - position.viewportDimension).clamp(0, position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final line = _line(metrics);

    // Страница для `PgUp`/`PgDn` известна заранее: строк столько, сколько видно.
    widget.page?.size = widget.visibleRows;

    return Container(
      height: line * widget.visibleRows + metrics.strokeWidth * 2,
      decoration: BoxDecoration(
        color: colors.inputBackground,
        border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.inputRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          widget.rows.isEmpty
              ? Center(
                child: Text(widget.emptyMessage, style: theme.dialogLabelStyle.copyWith(color: colors.inputHint)),
              )
              : ListView.builder(
                controller: _scroll,
                // Строки одной высоты, и это не только про вид: с известным
                // шагом список знает, где какая, не построив ни одной, — отсюда
                // и мгновенная прокрутка к выбранной.
                itemExtent: line,
                itemCount: widget.rows.length,
                itemBuilder: (context, index) => _row(theme, widget.rows[index]),
              ),
    );
  }

  Widget _row(FcTheme theme, FoundRow row) {
    final colors = theme.colors;
    final metrics = theme.metrics;
    final base = TextStyle(fontFamily: theme.fonts.ui, fontSize: metrics.fontSize);

    if (row.isHeader) {
      // Заголовок каталога: тем же цветом, каким пути показаны везде, и без
      // отступа — от него отступают находки.
      return Container(
        padding: EdgeInsets.symmetric(horizontal: metrics.inputHorizontalPadding),
        alignment: Alignment.centerLeft,
        child: Text(
          row.path,
          style: base.copyWith(color: colors.pathText),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final current = row.index == widget.selected;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTap(row.index),
      child: Container(
        color: current ? colors.cursorBackground : null,
        // Подсветка — во всю ширину, отбит только текст: так же, как строка под
        // курсором в панели. Отступ — тот самый абзац из `mc`.
        padding: EdgeInsets.only(
          left: metrics.inputHorizontalPadding + metrics.dialogHorizontalPadding,
          right: metrics.inputHorizontalPadding,
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          row.node!.name,
          style: base.copyWith(color: current ? colors.cursorText : colors.dialogLabel),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
