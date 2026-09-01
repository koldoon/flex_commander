import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Находки в окне поиска: таблица постоянного размера, в рамке и **ленивая**.
///
/// Три свойства, и каждое отвечает за своё.
///
/// **Ленивая** — потому что находок бывают тысячи. Общий список окон
/// ([FcPickList]) собирает все строки разом: он стоит в окне, которое меряет
/// содержимое (`IntrinsicWidth`), а ленивый список на вопрос о собственной
/// ширине отвечать не умеет. Здесь этого вопроса нет вовсе: окно поиска берёт
/// ширину долей экрана ([DialogSpec.ownWidth]), и мерить его содержимое некому.
///
/// **Постоянного размера** — высота считается по числу строк и не зависит от
/// того, сколько нашлось. Окно не растёт по ходу работы и не прыгает под
/// курсором, когда находки идут пачками.
///
/// **В рамке** — пустая область должна читаться как «сюда придут находки», а не
/// как дыра непонятно подо что. Рамка та же, что у полей ввода: таблица стоит
/// в окне среди них.
class FoundTable extends StatefulWidget {
  const FoundTable({
    super.key,
    required this.nodes,
    required this.selected,
    required this.whereOf,
    required this.onTap,
    required this.rows,
    this.page,
    this.emptyMessage = '',
  });

  /// Что показывать. Строки собираются **по одной, по мере показа**: список
  /// целиком не строится никогда.
  final List<FsNode> nodes;

  /// Строка под курсором; -1 — ни одной.
  final int selected;

  /// Откуда находка — приписка справа.
  final String Function(FsNode node) whereOf;

  final void Function(int index) onTap;

  /// Сколько строк видно: высота таблицы считается по ним и больше ни по чему.
  final int rows;

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

  /// Подводит выбранную строку под обзор — тем же счётом, что и общий список.
  void _showSelected() {
    if (!_scroll.hasClients || widget.selected < 0) {
      return;
    }
    final line = _line(FcTheme.of(context).metrics);
    final top = widget.selected * line;
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

    // Страница для `PgUp`/`PgDn` известна заранее: строк столько, сколько видно,
    // и меряться после раскладки тут нечему.
    widget.page?.size = widget.rows;

    return Container(
      height: line * widget.rows + metrics.strokeWidth * 2,
      decoration: BoxDecoration(
        color: colors.inputBackground,
        border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.inputRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          widget.nodes.isEmpty
              ? Center(
                child: Text(widget.emptyMessage, style: theme.dialogLabelStyle.copyWith(color: colors.inputHint)),
              )
              : ListView.builder(
                controller: _scroll,
                // Строки одной высоты, и это не только про вид: с известным
                // шагом список знает, где какая, не построив ни одной, —
                // отсюда и мгновенная прокрутка к выбранной.
                itemExtent: line,
                itemCount: widget.nodes.length,
                itemBuilder: (context, index) => _row(theme, index),
              ),
    );
  }

  Widget _row(FcTheme theme, int index) {
    final colors = theme.colors;
    final metrics = theme.metrics;
    final node = widget.nodes[index];
    final current = index == widget.selected;

    final base = TextStyle(fontFamily: theme.fonts.ui, fontSize: metrics.fontSize);
    final bright = base.copyWith(color: current ? colors.cursorText : colors.dialogLabel);
    final dim = base.copyWith(color: colors.dialogText);
    final where = widget.whereOf(node);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTap(index),
      child: Container(
        color: current ? colors.cursorBackground : null,
        // Подсветка — во всю ширину, отбит только текст: так же, как строка под
        // курсором в панели.
        padding: EdgeInsets.symmetric(horizontal: metrics.inputHorizontalPadding),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(child: Text(node.name, style: bright, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (where.isNotEmpty) ...[
              SizedBox(width: metrics.columnGap),
              Text(
                where,
                style: dim.copyWith(fontFamily: theme.fonts.fixed, fontFamilyFallback: theme.fonts.fixedFallback),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
