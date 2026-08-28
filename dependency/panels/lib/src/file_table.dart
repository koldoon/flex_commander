import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'file_table_header.dart';
import 'file_table_row.dart';

/// Таблица файлов: заголовки колонок, вертикальные линейки на всю высоту и
/// прокручиваемый список строк.
class FileTable extends StatefulWidget {
  const FileTable({super.key, required this.panel});

  final Panel panel;

  @override
  State<FileTable> createState() => _FileTableState();
}

class _FileTableState extends State<FileTable> {
  /// Окно, в пределах которого два клика по одной строке считаются двойным.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  /// Прокрутка живёт по каталогу: у нового каталога и список другой, и место
  /// в нём своё. Контроллер поэтому пересоздаётся — начальное смещение задаётся
  /// только при создании.
  ScrollController _scroll = ScrollController();

  /// Каталог, под который построена нынешняя прокрутка.
  DirectoryNode? _scrolledDirectory;

  /// Высота видимой части списка и высота строки из последней разметки: по ним
  /// считается, докуда прокручивать новый список ещё до того, как он появится.
  double _listHeight = 0;
  double _rowHeight = 0;

  /// Высота строки заголовков: от неё считается, какая строка под курсором при
  /// перетаскивании. Запоминается там же, где и остальные размеры, — при
  /// разметке.
  double _headerHeight = 0;

  /// Команда копирования и её параметры — по именам, а не по классам: работа
  /// живёт в модуле файловых операций, а панели обязаны собираться без него.
  static const String copyCommandId = 'file.copy';
  static const String sourcesParam = 'sources';
  static const String destinationParam = 'destination';

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
    final panel = widget.panel;
    if (!identical(panel.directory, _scrolledDirectory)) {
      // Каталог сменился — прокрутку поставит сборка списка. Здесь этого
      // делать нельзя: сообщения приходят и до того, как курсор встанет на
      // место, и посчитанное смещение оказалось бы от старого курсора.
      return;
    }

    if (panel.cursorIndex == _lastCursorIndex) {
      return;
    }
    _lastCursorIndex = panel.cursorIndex;
    // Внутри одного каталога список уже на экране, и прокрутить его можно
    // после кадра: видно движение курсора, а не прыжок содержимого.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCursorVisible());
  }

  /// Готовит прокрутку нового каталога — до того, как список появится
  /// на экране.
  ///
  /// Прокручивать его после кадра нельзя: список успевает мелькнуть началом —
  /// заметнее всего это при выходе наверх, когда курсор встаёт на каталог (или
  /// архив), из которого вышли, а он далеко внизу. Строки одной высоты, поэтому
  /// смещение считается без разметки и уходит в новый контроллер: первый же
  /// кадр рисуется прокрученным.
  ///
  /// Делается это при сборке, а не по сообщению панели: пока каталог читается,
  /// сообщений приходит несколько, и курсор встаёт на место последним.
  ///
  /// Контроллер именно новый: начальное смещение задаётся только при создании.
  /// А ключ у списка меняется вместе с ним потому, что `Scrollable` бережёт
  /// положение, когда узнаёт свой прежний элемент, — и прокрутка прежнего
  /// каталога перетекла бы в новый.
  void _prepareScroll() {
    final panel = widget.panel;
    if (identical(panel.directory, _scrolledDirectory)) {
      return;
    }

    final previous = _scroll;
    _scrolledDirectory = panel.directory;
    _lastCursorIndex = panel.cursorIndex;
    _scroll = ScrollController(initialScrollOffset: _cursorOffset());

    // Прежний контроллер ещё привязан к списку, который сейчас на экране:
    // отпускать его можно только после того, как список сменится.
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  /// Куда прокрутить новый список, чтобы курсор был виден.
  ///
  /// Прокрутка минимальная: строка у нижнего края, если она ниже видимой части,
  /// и ноль, если список и так начинается с неё.
  double _cursorOffset() {
    if (_listHeight <= 0 || _rowHeight <= 0) {
      // Разметки ещё не было — считать не из чего; поправит `_ensureCursorVisible`.
      return 0;
    }

    final bottom = (widget.panel.cursorIndex + 1) * _rowHeight;
    final total = widget.panel.nodes.length * _rowHeight;
    return (bottom - _listHeight).clamp(0.0, math.max(0.0, total - _listHeight));
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
              // Те же размеры нужны прокрутке нового каталога, а она считается
              // до разметки: запоминаем то, что известно сейчас.
              _listHeight = listHeight;
              _rowHeight = theme.metrics.rowHeight;
              _headerHeight = theme.metrics.headerRowHeight;

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

              final content = Stack(
                children: [
                  if (contentWidth > constraints.maxWidth)
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)
                  else
                    table,
                  // Линейки идут поверх строк и на всю высоту таблицы: в
                  // референсе `PanelLine` объявлены после списка, поэтому
                  // подсветка курсора их не закрывает. Иначе в активной строке
                  // разделители колонок пропадали бы.
                  Positioned.fill(
                    // Рисунок, а не участник разметки: клики по строке должны
                    // проходить сквозь него.
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ColumnDividersPainter(
                          columns: columns,
                          widths: widths,
                          color: theme.colors.columnDivider,
                          inset: theme.metrics.strokeWidth,
                        ),
                      ),
                    ),
                  ),
                ],
              );

              // Перетаскивания может не быть вовсе — тогда таблица такая же,
              // как была: панель про мышь снаружи ничего не знает.
              final dnd = app.dragAndDrop;
              if (dnd == null) {
                return content;
              }
              return dnd.target(
                spotAt: _spotAt,
                onDrop: (spot, payload) => _handleDrop(app, spot, payload),
                builder: (context, hovered) => _withHighlight(theme, content, hovered),
              );
            },
          ),
    );
  }

  /// Что под курсором при перетаскивании — строка-каталог или сама панель.
  ///
  /// null означает «сюда нельзя», и это же гасит подсветку: человек видит отказ
  /// до того, как отпустит кнопку.
  DropSpot? _spotAt(Offset local) {
    final panel = widget.panel;
    final directory = panel.directory;
    if (directory == null || !panel.provider.canWrite) {
      return null;
    }
    final node = _nodeAt(local);
    // Бросок на строку-каталог кладёт **в неё**; на файл, на `..` и мимо строк
    // — в каталог, открытый в панели.
    if (node is DirectoryNode && node is! ParentDirNode) {
      return DropSpot(destination: node.pathString, node: node);
    }
    return DropSpot(destination: directory.pathString);
  }

  /// Строка под точкой — с поправкой на заголовки и прокрутку.
  FsNode? _nodeAt(Offset local) {
    if (_rowHeight <= 0 || local.dy < _headerHeight) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final index = ((local.dy - _headerHeight + offset) / _rowHeight).floor();
    final nodes = widget.panel.nodes;
    return index >= 0 && index < nodes.length ? nodes[index] : null;
  }

  /// Подсветка того, куда попадёт брошенное: строка или вся панель.
  Widget _withHighlight(FcTheme theme, Widget content, DropSpot? hovered) {
    if (hovered == null) {
      return content;
    }
    final color = theme.colors.cursorBackground;
    final width = theme.metrics.strokeWidth * 2;
    final node = hovered.node;
    final index = node == null ? -1 : widget.panel.nodes.indexOf(node);
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;

    return Stack(
      children: [
        content,
        if (index >= 0)
          Positioned(
            top: _headerHeight + index * _rowHeight - offset,
            left: 0,
            right: 0,
            height: _rowHeight,
            child: IgnorePointer(
              child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: color, width: width))),
            ),
          )
        else
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: color, width: width))),
            ),
          ),
      ],
    );
  }

  /// Брошенное копируется той же командой, что работает за `F5`.
  ///
  /// По идентификатору, а не по классу: копирование живёт в модуле файловых
  /// операций, а приложение обязано собираться без него — тогда бросок просто
  /// ничего не сделает.
  Future<void> _handleDrop(Application app, DropSpot spot, DropPayload payload) async {
    if (payload.paths.isEmpty) {
      return;
    }
    // Бросок делает панель активной — как и клик по ней: работа пойдёт **в
    // неё**, и человек должен видеть, где он теперь.
    app.activate(widget.panel);
    app.commands.run(
      copyCommandId,
      CommandInvocation(parameters: {sourcesParam: payload.paths, destinationParam: spot.destination}),
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
        _prepareScroll();

        // Ошибка чтения списка не убирает: не прочитался **новый** каталог, а
        // панель осталась в прежнем — с его содержимым, курсором и пометкой.
        // Стереть их значило бы отнять и `..`, и всё, чем отсюда уходят:
        // человек, ткнувшийся в чужой каталог, оказывался запертым в
        // сообщении. Про неудачу говорит строка состояния, и этого довольно.
        if (panel.nodes.isEmpty) {
          return const SizedBox.shrink();
        }

        return ListView.builder(
          // Новый каталог — новый список: положение прежнего в него не
          // переносится.
          key: ValueKey(_scrolledDirectory),
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
  void _handleRowTap(Application app, int index) {
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
  const _ColumnDividersPainter({required this.columns, required this.widths, required this.color, required this.inset});

  final List<ColumnSpec> columns;
  final List<double> widths;
  final Color color;

  /// На сколько линейка не доходит до низа.
  ///
  /// В референсе разделители колонок не сходятся с линейкой над строкой
  /// состояния: между ними остаётся волосок фона. Сойдись они — получился бы
  /// перекрёсток, и глаз читал бы его как рамку таблицы, которой нет.
  final double inset;

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
        canvas.drawLine(Offset(dx, 0), Offset(dx, size.height - inset), paint);
      }
      x += widths[i];
    }
  }

  @override
  bool shouldRepaint(_ColumnDividersPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.inset != inset ||
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
