import 'package:flutter/material.dart';

import '../../model/panel/column_spec.dart';
import '../../model/panel/sort_spec.dart';
import '../theme/app_theme.dart';
import '../theme/fc_icons.dart';

/// Строка заголовков колонок.
///
/// Три жеста в одной строке: клик по заголовку сортирует, перетаскивание
/// заголовка меняет порядок колонок, перетаскивание границы — их ширину.
/// Правый клик открывает меню видимости.
class FileTableHeader extends StatefulWidget {
  const FileTableHeader({
    super.key,
    required this.layout,
    required this.columns,
    required this.widths,
    required this.sort,
    this.onColumnTap,
    this.onLayoutChanged,
  });

  /// Полная раскладка, включая скрытые колонки: перестановка и видимость
  /// работают именно с ней.
  final ColumnLayout layout;

  /// Видимые колонки — то, что реально нарисовано.
  final List<ColumnSpec> columns;

  final List<double> widths;
  final SortSpec sort;

  final void Function(FsColumn column)? onColumnTap;
  final void Function(ColumnLayout layout)? onLayoutChanged;

  @override
  State<FileTableHeader> createState() => _FileTableHeaderState();
}

class _FileTableHeaderState extends State<FileTableHeader> {
  /// Перетаскиваемая колонка и позиция, куда её положат.
  FsColumn? _dragged;
  int _dropIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return SizedBox(
      height: theme.metrics.headerRowHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) => _showColumnsMenu(context, details.globalPosition),
        child: Stack(
          children: [
            // Строка растягивается на всю высоту заголовка, иначе Stack
            // прижмёт её к верхнему краю и текст съедет с середины.
            Positioned.fill(
              child: Row(
                children: [
                  for (var i = 0; i < widget.columns.length; i++)
                    SizedBox(width: widget.widths[i], child: _cell(i, theme)),
                ],
              ),
            ),
            if (_dropIndex >= 0) _dropMarker(theme),
            ..._resizeHandles(theme),
          ],
        ),
      ),
    );
  }

  Widget _cell(int index, FcTheme theme) {
    final column = widget.columns[index];
    final movable = !column.pinned && widget.onLayoutChanged != null;

    final cell = FileTableHeaderCell(
      column: column,
      sorted: widget.sort.column == column.id,
      direction: widget.sort.direction,
      onTap: widget.onColumnTap == null || !column.id.sortable ? null : () => widget.onColumnTap!(column.id),
    );

    if (!movable) {
      return cell;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Тап и перетаскивание уживаются в одном месте: без движения срабатывает
      // сортировка, с движением — перестановка колонки.
      onHorizontalDragStart:
          (_) => setState(() {
            _dragged = column.id;
            _dropIndex = index;
          }),
      onHorizontalDragUpdate: (details) => _updateDropIndex(details.localPosition.dx, index),
      onHorizontalDragEnd: (_) => _finishDrag(),
      onHorizontalDragCancel: _cancelDrag,
      child: Opacity(opacity: _dragged == column.id ? 0.4 : 1, child: cell),
    );
  }

  /// Полоса, показывающая, куда встанет колонка.
  Widget _dropMarker(FcTheme theme) {
    var offset = 0.0;
    for (var i = 0; i < _dropIndex && i < widget.widths.length; i++) {
      offset += widget.widths[i];
    }
    return Positioned(
      left: offset - 1,
      top: 0,
      bottom: 0,
      width: 2,
      child: ColoredBox(color: theme.colors.cursorBackground),
    );
  }

  /// Невидимые полосы захвата на границах колонок фиксированной ширины.
  ///
  /// Граница — это левый край колонки, поэтому перетаскивание влево её
  /// расширяет; «резиновая» колонка имени поглощает разницу.
  List<Widget> _resizeHandles(FcTheme theme) {
    if (widget.onLayoutChanged == null) {
      return const [];
    }

    final handles = <Widget>[];
    var offset = 0.0;
    for (var i = 0; i < widget.columns.length; i++) {
      final column = widget.columns[i];
      if (i > 0 && !column.flexible) {
        handles.add(
          Positioned(
            left: offset - theme.metrics.resizeHandleWidth / 2,
            top: 0,
            bottom: 0,
            width: theme.metrics.resizeHandleWidth,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) => _resize(column, -details.delta.dx),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      }
      offset += widget.widths[i];
    }
    return handles;
  }

  void _resize(ColumnSpec column, double delta) {
    final layout = widget.layout.resize(column.id, column.width + delta);
    widget.onLayoutChanged?.call(layout);
  }

  void _updateDropIndex(double dx, int index) {
    // Локальная координата приходит относительно ячейки, поэтому переводим её
    // в координаты всей строки заголовков.
    var start = 0.0;
    for (var i = 0; i < index; i++) {
      start += widget.widths[i];
    }
    final x = start + dx;

    var offset = 0.0;
    var target = widget.columns.length;
    for (var i = 0; i < widget.columns.length; i++) {
      if (x < offset + widget.widths[i] / 2) {
        target = i;
        break;
      }
      offset += widget.widths[i];
    }

    if (target != _dropIndex) {
      setState(() => _dropIndex = target);
    }
  }

  void _finishDrag() {
    final dragged = _dragged;
    final dropIndex = _dropIndex;
    _cancelDrag();

    if (dragged == null || dropIndex < 0) {
      return;
    }

    final layout = widget.layout;
    final from = layout.indexOf(dragged);
    // Позиция среди видимых колонок переводится в позицию в полной раскладке.
    final to =
        dropIndex >= widget.columns.length ? layout.columns.length - 1 : layout.indexOf(widget.columns[dropIndex].id);

    final moved = layout.moveColumn(from, to);
    if (!identical(moved, layout)) {
      widget.onLayoutChanged?.call(moved);
    }
  }

  void _cancelDrag() {
    if (_dragged == null && _dropIndex < 0) {
      return;
    }
    setState(() {
      _dragged = null;
      _dropIndex = -1;
    });
  }

  Future<void> _showColumnsMenu(BuildContext context, Offset position) async {
    final onLayoutChanged = widget.onLayoutChanged;
    if (onLayoutChanged == null) {
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final layout = widget.layout;

    final selected = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
      items: [
        for (final column in layout.columns)
          CheckedPopupMenuItem<Object>(
            value: column.id,
            checked: column.visible,
            // Иконку и имя скрывать нельзя: без них строка нечитаема.
            enabled: !column.pinned,
            child: Text(FileTableHeaderCell.titleOf(column.id)),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(value: _resetLayout, child: Text('Reset columns')),
      ],
    );

    if (selected == _resetLayout) {
      onLayoutChanged(ColumnLayout.defaults);
    } else if (selected is FsColumn) {
      onLayoutChanged(layout.toggleVisible(selected));
    }
  }

  static const String _resetLayout = 'reset';
}

/// Заголовок одной колонки с индикатором сортировки.
class FileTableHeaderCell extends StatelessWidget {
  const FileTableHeaderCell({
    super.key,
    required this.column,
    required this.sorted,
    required this.direction,
    this.onTap,
  });

  final ColumnSpec column;
  final bool sorted;
  final SortDirection direction;
  final VoidCallback? onTap;

  static String titleOf(FsColumn column) => _titles[column] ?? column.name;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final title = titleOf(column.id);
    if (column.id == FsColumn.icon) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: theme.metrics.cellPadding),
          child: Row(
            // Заголовки в референсе выровнены по центру колонки независимо от
            // того, как выровнено её содержимое (`horizontalAlign="center"`).
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Треугольник стоит перед текстом — как в референсе, и теми же
              // глифами (`fa_caret_down` / `fa_caret_up`).
              if (sorted) ...[
                Icon(
                  direction == SortDirection.ascending ? FcIcons.caretDown : FcIcons.caretUp,
                  size: theme.metrics.iconSize,
                  color: theme.colors.headerText,
                ),
                SizedBox(width: theme.metrics.cellPadding),
              ],
              Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.clip, style: theme.headerStyle)),
            ],
          ),
        ),
      ),
    );
  }

  static const Map<FsColumn, String> _titles = {
    FsColumn.icon: '',
    FsColumn.name: 'Name',
    FsColumn.ext: 'Ext',
    FsColumn.size: 'Size',
    FsColumn.modified: 'Modified',
    FsColumn.created: 'Created',
    FsColumn.accessed: 'Accessed',
    FsColumn.attributes: 'Attributes',
  };
}
