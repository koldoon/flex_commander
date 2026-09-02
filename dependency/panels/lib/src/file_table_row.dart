import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'file_type_icon.dart';

/// Одна строка файловой таблицы.
///
/// Состояния накладываются снизу вверх: обычная → помеченная → под курсором.
/// Курсор рисуется только в активной панели; пометка видна в обеих.
class FileTableRow extends StatelessWidget {
  const FileTableRow({
    super.key,
    required this.entry,
    required this.columns,
    required this.widths,
    required this.marked,
    required this.underCursor,
    required this.panelActive,
    this.naming = const ReferenceFileNaming(),
    this.onTap,
  });

  /// Строка значением: узлы живут в ядре, а рисуют по эту сторону.
  final FileEntry entry;
  final List<ColumnSpec> columns;
  final List<double> widths;
  final bool marked;
  final bool underCursor;
  final bool panelActive;

  /// Чем имя делится на имя и расширение.
  ///
  /// Расширения у файла нет — есть имя, а расширение это его толкование, и оно
  /// принадлежит тому, кто показывает. Здесь толкует **эта** реализация панели,
  /// у которой есть колонка `Ext`; дерево или миниатюры покажут имя иначе, и
  /// спрашивать их о расширении будет бессмысленно.
  final FileNaming naming;

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
              // Содержимое опущено относительно подсветки — см.
              // `FcMetrics.rowContentVerticalNudge`. Сдвиг не меняет разметку,
              // поэтому шаг строк остаётся прежним.
              Transform.translate(
                offset: Offset(0, theme.metrics.rowContentVerticalNudge),
                child: Row(
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      SizedBox(width: widths[i], child: _cell(context, theme, columns[i])),
                  ],
                ),
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
        child: Align(alignment: Alignment.centerLeft, child: FileTypeIcon(entry: entry, selected: _selected)),
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
    if (entry.isParent) {
      // У «..» есть только имя: размер и даты родительского каталога здесь
      // ничего не значат.
      return column.id == FsColumn.name ? entry.name : '';
    }

    // У каталога расширения нет: `my.backup` это не «файл .backup». Решает это
    // тот, кто показывает, — расширение вообще не свойство файла, а толкование
    // имени.
    final splittable = !entry.isDirectory;
    return switch (column.id) {
      // Расширение показывается отдельной колонкой, поэтому из имени убирается.
      FsColumn.name => _showExtension && splittable ? naming.split(entry.name).base : entry.name,
      FsColumn.ext => _showExtension && splittable ? naming.split(entry.name).extension : '',
      // Каталог объекта, а не его собственный путь: имя уже показано рядом.
      FsColumn.path => entry.directoryPath,
      FsColumn.size => formatSize(entry.size),
      FsColumn.modified => formatDate(entry.modified),
      FsColumn.created => formatDate(entry.created),
      FsColumn.accessed => formatDate(entry.accessed),
      FsColumn.attributes => entry.attributes.modeString,
      FsColumn.icon => '',
    };
  }

  /// Расширение отделяется от имени, только если колонка расширений видима.
  bool get _showExtension => columns.any((column) => column.id == FsColumn.ext);
}
