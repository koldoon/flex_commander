import 'package:flutter/material.dart';

import '../../model/panel/column_spec.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../state/panel_controller.dart';
import '../theme/app_theme.dart';
import 'file_table_header.dart';
import 'file_table_row.dart';

/// Таблица файлов: заголовки колонок, вертикальные линейки на всю высоту и
/// прокручиваемый список строк.
class FileTable extends StatefulWidget {
  const FileTable({super.key, required this.panel});

  final PanelController panel;

  @override
  State<FileTable> createState() => _FileTableState();
}

class _FileTableState extends State<FileTable> {
  /// Окно, в пределах которого два клика по одной строке считаются двойным.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  final ScrollController _scroll = ScrollController();
  int _lastCursorIndex = -1;

  int _lastTapIndex = -1;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    widget.panel.addListener(_onPanelChanged);
  }

  @override
  void didUpdateWidget(FileTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel != widget.panel) {
      oldWidget.panel.removeListener(_onPanelChanged);
      widget.panel.addListener(_onPanelChanged);
    }
  }

  @override
  void dispose() {
    widget.panel.removeListener(_onPanelChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onPanelChanged() {
    if (widget.panel.cursorIndex == _lastCursorIndex) {
      return;
    }
    _lastCursorIndex = widget.panel.cursorIndex;
    // Прокрутка выполняется после кадра: к этому моменту список уже знает
    // свои размеры и число строк.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCursorVisible());
  }

  /// Держит курсор в видимой части списка. Прокрутка мгновенная: в файловом
  /// менеджере анимация только мешает быстрому перебору клавишами.
  void _ensureCursorVisible() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    final rowHeight = FcTheme.of(context).metrics.rowHeight;
    final position = _scroll.position;
    final top = widget.panel.cursorIndex * rowHeight;
    final bottom = top + rowHeight;

    double? target;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = bottom - position.viewportDimension;
    }
    if (target != null) {
      _scroll.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final panel = widget.panel;

    return ListenableBuilder(
      // Раскладка колонок и правило сортировки живут в панели: их изменение
      // должно пересчитывать ширины и перерисовывать заголовки.
      listenable: panel,
      builder:
          (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final app = AppScope.read(context);
              final columns = panel.columns.visibleColumns;
              // Поле справа принадлежит содержимому, а не подсветке строки:
              // `right="40"` у содержимого строки при рамке панели, идущей
              // до самого края.
              final inset = theme.metrics.panelRightPadding;
              final widths = _columnWidths(columns, constraints.maxWidth - inset);
              final contentWidth = widths.fold<double>(0, (sum, width) => sum + width) + inset;

              // Сколько строк видно — от этого считается шаг PgUp/PgDn.
              final listHeight = constraints.maxHeight - theme.metrics.headerRowHeight;
              panel.pageSize = (listHeight / theme.metrics.rowHeight).floor().clamp(1, 1000);

              final table = SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FileTableHeader(
                      layout: panel.columns,
                      columns: columns,
                      widths: widths,
                      sort: panel.sort,
                      onColumnTap: (column) {
                        app.activate(panel);
                        panel.sortBy(column);
                      },
                      onLayoutChanged: (layout) {
                        app.activate(panel);
                        panel.setColumnLayout(layout);
                      },
                    ),
                    Expanded(child: _buildList(columns, widths)),
                  ],
                ),
              );

              return Stack(
                children: [
                  // Линейки рисуются под содержимым и на всю высоту таблицы —
                  // как в макете, где они идут от заголовков до строки состояния.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ColumnDividersPainter(
                        columns: columns,
                        widths: widths,
                        color: theme.colors.columnDivider,
                      ),
                    ),
                  ),
                  if (contentWidth > constraints.maxWidth)
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)
                  else
                    table,
                ],
              );
            },
          ),
    );
  }

  Widget _buildList(List<ColumnSpec> columns, List<double> widths) {
    final panel = widget.panel;
    final theme = FcTheme.of(context);
    // Контроллер берётся из контекста таблицы, а не из контекста строки:
    // строки пересобираются, и к моменту обработки клика элемент строки
    // может быть уже отсоединён от дерева.
    final app = AppScope.read(context);

    return ListenableBuilder(
      // Строки перерисовываются и при движении курсора, и при изменении
      // пометки; ListView строит только видимые, поэтому это дёшево.
      listenable: Listenable.merge([panel, panel.selection]),
      builder: (context, _) {
        if (panel.status == PanelStatus.error) {
          return _PanelMessage(text: panel.error?.message ?? 'Error');
        }
        if (panel.nodes.isEmpty) {
          return const SizedBox.shrink();
        }

        return ListView.builder(
          controller: _scroll,
          itemExtent: theme.metrics.rowHeight,
          itemCount: panel.nodes.length,
          primary: false,
          itemBuilder: (context, index) {
            final node = panel.nodes[index];
            return FileTableRow(
              node: node,
              columns: columns,
              widths: widths,
              marked: panel.selection.contains(node),
              underCursor: index == panel.cursorIndex,
              panelActive: panel.active,
              onTap: () => _handleRowTap(app, index),
            );
          },
        );
      },
    );
  }

  /// Клик ставит курсор, двойной клик по той же строке — входит в объект.
  ///
  /// Двойной клик распознаётся вручную: штатный `onDoubleTap` заставляет
  /// Flutter придержать одиночный клик до истечения таймаута, а курсор в
  /// файловом менеджере должен переставляться сразу.
  void _handleRowTap(AppController app, int index) {
    final now = DateTime.now();
    final isDoubleTap = index == _lastTapIndex && now.difference(_lastTapTime) < _doubleTapWindow;
    _lastTapIndex = index;
    _lastTapTime = now;

    app.activate(widget.panel);
    widget.panel.setCursorIndex(index);

    if (isDoubleTap) {
      _lastTapIndex = -1;
      widget.panel.enterCurrent();
    }
  }

  /// Фиксированные колонки получают свою ширину, «резиновая» — весь остаток.
  /// Если остатка не хватает, она сжимается до минимума, а таблица начинает
  /// прокручиваться по горизонтали.
  List<double> _columnWidths(List<ColumnSpec> columns, double available) {
    var fixed = 0.0;
    for (final column in columns) {
      if (!column.flexible) {
        fixed += column.width;
      }
    }

    final rest = available - fixed;
    return [
      for (final column in columns)
        if (column.flexible) (rest < column.minWidth ? column.minWidth : rest) else column.width,
    ];
  }
}

/// Вертикальные линейки между колонками.
///
/// Линейка не рисуется между именем и расширением: расширение — продолжение
/// имени, а не отдельная величина (так же в макете).
class _ColumnDividersPainter extends CustomPainter {
  const _ColumnDividersPainter({required this.columns, required this.widths, required this.color});

  final List<ColumnSpec> columns;
  final List<double> widths;
  final Color color;

  static const Set<FsColumn> _noLeftDivider = {FsColumn.icon, FsColumn.name, FsColumn.ext};

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1;

    var x = 0.0;
    for (var i = 0; i < columns.length; i++) {
      if (i > 0 && !_noLeftDivider.contains(columns[i].id)) {
        final dx = x.roundToDouble() + 0.5;
        canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      }
      x += widths[i];
    }
  }

  @override
  bool shouldRepaint(_ColumnDividersPainter oldDelegate) =>
      oldDelegate.color != color ||
      !identical(oldDelegate.columns, columns) ||
      !_sameWidths(oldDelegate.widths, widths);

  static bool _sameWidths(List<double> a, List<double> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, textAlign: TextAlign.center, style: theme.rowStyle.copyWith(color: theme.colors.error)),
      ),
    );
  }
}
