import 'package:flutter/material.dart';

import '../../model/panel/column_spec.dart';
import '../../model/panel/sort_spec.dart';
import '../theme/app_theme.dart';

/// Строка заголовков колонок.
class FileTableHeader extends StatelessWidget {
  const FileTableHeader({super.key, required this.columns, required this.widths, required this.sort, this.onColumnTap});

  final List<ColumnSpec> columns;
  final List<double> widths;
  final SortSpec sort;
  final void Function(FsColumn column)? onColumnTap;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return SizedBox(
      height: theme.metrics.headerRowHeight,
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: widths[i],
              child: FileTableHeaderCell(
                column: columns[i],
                sorted: sort.column == columns[i].id,
                direction: sort.direction,
                onTap: onColumnTap == null || !columns[i].id.sortable ? null : () => onColumnTap!(columns[i].id),
              ),
            ),
        ],
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final title = _titles[column.id] ?? '';
    if (title.isEmpty) {
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
            mainAxisAlignment: column.align == ColumnAlign.end ? MainAxisAlignment.end : MainAxisAlignment.center,
            children: [
              // Треугольник стоит перед текстом — как в макете и в референсе.
              if (sorted)
                Icon(
                  direction == SortDirection.ascending ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                  size: theme.metrics.iconSize,
                  color: theme.colors.headerText,
                ),
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
