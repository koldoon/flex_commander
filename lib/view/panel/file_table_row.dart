import 'package:flutter/material.dart';

import '../../model/panel/column_spec.dart';
import '../../model/tree/fs_node.dart';
import '../format/date_format.dart';
import '../format/size_format.dart';
import '../theme/app_theme.dart';
import 'file_type_icon.dart';

/// Одна строка файловой таблицы.
///
/// Состояния накладываются снизу вверх: обычная → помеченная → под курсором.
/// Курсор рисуется только в активной панели; пометка видна в обеих.
class FileTableRow extends StatelessWidget {
  const FileTableRow({
    super.key,
    required this.node,
    required this.columns,
    required this.widths,
    required this.marked,
    required this.underCursor,
    required this.panelActive,
    this.onTap,
  });

  final FsNode node;
  final List<ColumnSpec> columns;
  final List<double> widths;
  final bool marked;
  final bool underCursor;
  final bool panelActive;

  final VoidCallback? onTap;

  bool get _selected => underCursor && panelActive;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Просвет между строками: подсветка курсора и пометки не смыкается
      // со следующей строкой. Нажатие по просвету всё равно попадает в строку —
      // отступ лежит внутри области жеста.
      child: Padding(
        padding: EdgeInsets.only(bottom: theme.metrics.rowGap),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                _selected
                    ? colors.cursorBackground
                    : marked
                    ? colors.markedBackground
                    : null,
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < columns.length; i++)
                    SizedBox(width: widths[i], child: _cell(context, theme, columns[i])),
                ],
              ),
              // Полоса пометки поверх фона: она должна читаться и тогда, когда
              // строка вдобавок под курсором.
              if (marked)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: theme.metrics.markedBarWidth,
                  child: ColoredBox(color: colors.markedBar),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, FcTheme theme, ColumnSpec column) {
    final metrics = theme.metrics;

    if (column.id == FsColumn.icon) {
      // Иконка прижата к левому краю строки: `left="30"` у `iconLabel`.
      return Padding(
        padding: EdgeInsets.only(left: metrics.iconLeftPadding),
        child: Align(alignment: Alignment.centerLeft, child: FileTypeIcon(node: node, selected: _selected)),
      );
    }

    final text = _textFor(column);
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding),
      child: Align(
        alignment: column.align == ColumnAlign.end ? Alignment.centerRight : Alignment.centerLeft,
        // Текст опущен относительно иконки — см. `FcMetrics.textVerticalNudge`.
        child: Transform.translate(
          offset: Offset(0, metrics.rowTextVerticalNudge),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: column.align == ColumnAlign.end ? TextAlign.right : TextAlign.left,
            style: _styleFor(theme, column),
          ),
        ),
      ),
    );
  }

  /// В референсе все ячейки строки одного цвета, а под курсором — белые:
  /// тип объекта показывает иконка, а не цвет имени.
  TextStyle _styleFor(FcTheme theme, ColumnSpec column) {
    final base = theme.rowStyle;
    return _selected ? base.copyWith(color: theme.colors.cursorText) : base;
  }

  String _textFor(ColumnSpec column) {
    if (node is ParentDirNode) {
      // У «..» есть только имя: размер и даты родительского каталога здесь
      // ничего не значат.
      return column.id == FsColumn.name ? node.name : '';
    }

    final file = node is FileNode ? node as FileNode : null;
    return switch (column.id) {
      // Расширение показывается отдельной колонкой, поэтому из имени убирается.
      FsColumn.name => _showExtension ? (file?.baseName ?? node.name) : node.name,
      FsColumn.ext => _showExtension ? (file?.extension ?? '') : '',
      FsColumn.size => formatSize(node.size),
      FsColumn.modified => formatDate(file?.modified),
      FsColumn.created => formatDate(file?.created),
      FsColumn.accessed => formatDate(file?.accessed),
      FsColumn.attributes => file?.attributes.modeString ?? '',
      FsColumn.icon => '',
    };
  }

  /// Расширение отделяется от имени, только если колонка расширений видима.
  bool get _showExtension => columns.any((column) => column.id == FsColumn.ext);
}
