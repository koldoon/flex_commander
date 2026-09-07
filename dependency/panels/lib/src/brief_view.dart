import 'dart:async';
import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'cursor_pin.dart';
import 'file_table_row.dart';
import 'panel_drag.dart';
import 'panels_settings.dart';

/// Краткий вид: одни имена, столбцами сверху вниз и дальше вправо.
///
/// Спецификация — `docs/spec/panel-view-brief.md`.
///
/// Раскладка одного и того же списка, а не второй список: курсор, пометка и
/// порядок — панельные, и вид их только показывает
/// (`docs/spec/panel-views.md`, §4).
class BriefView extends StatefulWidget {
  const BriefView({super.key, required this.panel, required this.settings});

  /// Имя вида — оно же ключ настройки панели.
  static const String viewId = 'brief';

  final Panel panel;

  /// Способ узнать настройки, а не их значение: их правят в окне выбора вида, и
  /// следующая же отрисовка должна идти по новым.
  final PanelsSettings Function() settings;

  @override
  State<BriefView> createState() => _BriefViewState();
}

class _BriefViewState extends State<BriefView> {
  /// Окно, в пределах которого два щелчка по одной строке считаются двойным.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  /// Список сразу встаёт туда, где стоял: начальное смещение задаётся при
  /// создании контроллера, а не подмоткой следующим кадром.
  ///
  /// Иначе возврат из полноэкранного вида видно глазами: вид на миг
  /// показывает начало и только потом прыгает на место.
  late final ScrollController _scroll = ScrollController(initialScrollOffset: widget.panel.scrollOffset);

  /// Прокрутку запомнили — можно о ней и рассказывать.
  bool _shown = false;

  /// Раскладка последней отрисовки: по ней прокрутка держит курсор на виду ещё
  /// до того, как случится следующая.
  double _columnWidth = 0;
  double _viewWidth = 0;
  int _rows = 1;

  /// Строка под курсором с прошлого показа — чтобы перестановка её не сдвинула.
  final CursorPin _pin = CursorPin();

  /// Высота строки последней отрисовки: по ней ищут строку под указателем.
  double _rowHeight = 0;

  int _lastCursorIndex = -1;
  int _lastTapIndex = -1;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Список, для которого мерили самое длинное имя, и сама мера.
  ///
  /// Мерить на каждую отрисовку нельзя: в каталоге бывают тысячи имён. Список
  /// приходит значением и на каждое чтение новый — по нему и видно, что мерить
  /// пора заново.
  List<FileEntry>? _measuredList;
  double _measuredWidth = 0;

  @override
  void initState() {
    super.initState();
    _askRows();
  }

  @override
  void didUpdateWidget(BriefView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel != widget.panel) {
      _askRows();
    }
  }

  /// Вид говорит, что ему нужно: строки каталога.
  ///
  /// Молчание значило бы «сойдёт и то, что дали», а дали бы то, что просил
  /// прежний вид, — дерево (`docs/spec/panel-node-list.md`, §3).
  ///
  /// После кадра, а не посреди него: на петле ядро отвечает в том же обороте, и
  /// смена набора строк перерисовывала бы дерево виджетов из чужой сборки.
  void _askRows() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.panel.showRows(RowsKind.listing));
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Ширина самого длинного имени — тем же набором, каким его нарисуют.
  double _widestName(BuildContext context, FcTheme theme, List<FileEntry> entries) {
    if (identical(_measuredList, entries)) {
      return _measuredWidth;
    }
    _measuredList = entries;
    _measuredWidth = widestLabel(
      context,
      [for (final entry in entries) entry.name],
      style: theme.rowStyle,
      limit: 4000,
    );
    return _measuredWidth;
  }

  /// Докрутить так, чтобы столбец с курсором стоял целиком.
  ///
  /// По столбцам, а не по точкам: столбец — единица раскладки, и половина
  /// столбца у края читалась бы обрезком.
  void _revealCursor() {
    if (!_scroll.hasClients || _columnWidth <= 0 || _viewWidth <= 0) {
      return;
    }
    final rows = widget.panel.entries;
    final at = widget.panel.cursorIndex;
    final column = at ~/ _rows;

    // Список переставили — столбец с курсором остаётся там же, где был: то же
    // правило, что и при смене раскладки, только повод другой
    // (`docs/spec/panel-views.md`, §9). Запоминается **всегда**, флажок или
    // нет: иначе после выключения и включения закрепление сработало бы от
    // устаревшего места.
    final from = widget.settings().cursorHoldsPlace ? _pin.movedFrom(rows, at) : null;
    _pin.remember(rows, at);
    final offset =
        from == null
            ? _scroll.offset
            : (_scroll.offset + (column - from ~/ _rows) * _columnWidth).clamp(0.0, _scroll.position.maxScrollExtent);

    final left = column * _columnWidth;
    final right = left + _columnWidth;
    final target = switch (0) {
      _ when left < offset => left,
      _ when right > offset + _viewWidth => right - _viewWidth,
      _ => offset,
    };
    if (target != _scroll.offset) {
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  /// Где на экране левый край столбца с курсором; null — прокрутки ещё нет.
  ///
  /// Считается **до** новой раскладки, по прежним числам: после неё столбец у
  /// курсора другой, и вернуть его на место можно только зная, где он был.
  double? _cursorColumnOnScreen() {
    if (!_scroll.hasClients || _columnWidth <= 0 || _rows <= 0) {
      return null;
    }
    final column = widget.panel.cursorIndex ~/ _rows;
    return column * _columnWidth - _scroll.offset;
  }

  /// Вернуть столбец с курсором туда же, где он стоял на экране.
  ///
  /// Не влез — обычная докрутка: обещание «ничего не поехало» кончается там,
  /// где столбец перестал помещаться.
  void _pinCursorColumn(double? was) {
    if (!_scroll.hasClients || was == null || _columnWidth <= 0) {
      _revealCursor();
      return;
    }
    final column = widget.panel.cursorIndex ~/ _rows;
    final target = column * _columnWidth - was;
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    _revealCursor();
  }

  /// Номер строки под точкой — в местных координатах области; null — мимо.
  ///
  /// Столбцы едут вбок, строки идут сверху вниз: место в списке складывается из
  /// того и другого.
  int? _indexAt(Offset local) {
    if (_columnWidth <= 0 || _rowHeight <= 0 || _rows <= 0) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final column = ((local.dx + offset) / _columnWidth).floor();
    final row = (local.dy / _rowHeight).floor();
    if (column < 0 || row < 0 || row >= _rows) {
      return null;
    }
    final index = column * _rows + row;
    return index >= 0 && index < widget.panel.entries.length ? index : null;
  }

  /// Куда попадёт брошенное: в каталог под указателем, а мимо каталогов — в
  /// каталог панели. То же правило, что у таблицы.
  DropSpot? _spotAt(Offset local) {
    final panel = widget.panel;
    if (panel.currentPath.isEmpty || !panel.source.canWrite) {
      return null;
    }
    final index = _indexAt(local);
    final entry = index == null ? null : panel.entries[index];
    if (entry != null && entry.isDirectory && !entry.isParent) {
      return DropSpot(destination: entry.path, entry: entry);
    }
    return DropSpot(destination: panel.currentPath);
  }

  /// Обводится **ячейка**: у краткого вида строка занимает столбец, а не всю
  /// ширину области.
  Rect? _highlightOf(DropSpot spot) {
    final entry = spot.entry;
    final index = entry == null ? -1 : widget.panel.entries.indexOf(entry);
    if (index < 0 || _columnWidth <= 0 || _rows <= 0) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final column = index ~/ _rows;
    final row = index % _rows;
    return Rect.fromLTWH(column * _columnWidth - offset, row * _rowHeight, _columnWidth, _rowHeight);
  }

  void _onTap(int index) {
    final panel = widget.panel;
    final now = DateTime.now();
    final again = index == _lastTapIndex && now.difference(_lastTapTime) < _doubleTapWindow;
    _lastTapIndex = index;
    _lastTapTime = now;

    AppScope.read(context).activate(panel);
    panel.setCursorIndex(index);
    if (again) {
      panel.enterCurrent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: panel,
      builder:
          (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final app = AppScope.read(context);
              final entries = panel.entries;
              final metrics = theme.metrics;

              // Те же величины, что у таблицы: строки обоих видов обязаны
              // совпадать по ритму, а размер значка задаёт их высоту.
              final iconSize = FileIconSize.of(metrics, app.fileIcons);
              final rowHeight = FileIconSize.rowHeight(metrics, iconSize);
              final iconWidth = FileIconSize.columnWidth(metrics, iconSize);

              final rows = math.max(1, (constraints.maxHeight / rowHeight).floor());
              final total = entries.isEmpty ? 0 : (entries.length / rows).ceil();

              // Сколько столбцов помещается — или сколько просили. Просьба
              // главнее ширины: в этом и смысл настройки.
              final asked = widget.settings().briefColumns;
              final inset = metrics.panelRightPadding;
              final available = math.max(constraints.maxWidth - inset, 1.0);
              final needed = _widestName(context, theme, entries) + iconWidth + metrics.cellPadding * 2;
              final columnWidth =
                  asked > PanelsSettings.autoColumns
                      ? available / asked
                      : math.min(math.max(needed, available / PanelsSettings.maxColumns), available);
              final visible = math.max(1, (available / columnWidth).floor());

              panel.pageSize = (rows * visible).clamp(1, 10000);
              // Столбцы есть — значит, `Left`/`Right` ходят по ним.
              panel.columnRows = rows;

              // Окно изменили — раскладка другая: столбцов стало больше или
              // меньше, ширина у них новая. Прокрутка при этом остаётся в
              // точках и указывает уже не туда: содержимое «плывёт» под
              // обзором. Держимся за курсор — он и есть то место, на которое
              // человек смотрит (`docs/spec/panel-view-brief.md`, §7).
              _rowHeight = rowHeight;
              final resized = _rows != rows || _columnWidth != columnWidth || _viewWidth != available;
              final wasCursorAt = _cursorColumnOnScreen();
              _rows = rows;
              _columnWidth = columnWidth;
              _viewWidth = available;
              if (resized) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _pinCursorColumn(wasCursorAt));
              }

              // Курсор мог уехать за край чужими руками — стрелкой, поиском,
              // сменой каталога. Проверяется после разметки: до неё прокрутки
              // ещё нет.
              if (_lastCursorIndex != panel.cursorIndex) {
                _lastCursorIndex = panel.cursorIndex;
                WidgetsBinding.instance.addPostFrameCallback((_) => _revealCursor());
              }

              final widths = <double>[iconWidth, math.max(columnWidth - iconWidth, 1)];

              final list = ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemExtent: columnWidth,
                itemCount: total,
                itemBuilder: (context, column) {
                  final first = column * rows;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var row = 0; row < rows && first + row < entries.length; row++)
                        SizedBox(
                          height: rowHeight,
                          // Строку можно утащить — тем же жестом и по тому же
                          // правилу, что в таблице (`panel_drag.dart`).
                          child: panelDragSource(
                            context: context,
                            panel: panel,
                            entry: entries[first + row],
                            child: FileTableRow(
                              entry: entries[first + row],
                              columns: _briefColumns,
                              widths: widths,
                              marked: panel.isMarked(entries[first + row]),
                              underCursor: panel.cursorIndex == first + row,
                              // Тот же вопрос, что задаёт плашка пути: горит
                              // курсор там, где сейчас клавиши.
                              panelActive: app.view.takesKeys(panel),
                              naming: app.fileNaming,
                              contentOf: panel.contentOf,
                              onTap: () => _onTap(first + row),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );

              return PanelDropArea(
                panel: panel,
                spotAt: _spotAt,
                highlightOf: _highlightOf,
                child: NotificationListener<ScrollEndNotification>(
                  // Прокрутка запоминается, когда устоялась: с неё вид и
                  // начнёт, когда его соберут заново — после полноэкранного
                  // просмотра или перезапуска.
                  onNotification: (notification) {
                    if (_shown) {
                      panel.setScrollOffset(notification.metrics.pixels);
                    }
                    _shown = true;
                    return false;
                  },
                  child: list,
                ),
              );
            },
          ),
    );
  }
}

/// Колонки строки краткого вида: значок и имя целиком.
///
/// Строка та же, что в таблице, — и цвета, и полоса пометки, и просвет между
/// строками достаются даром. Колонки расширения здесь нет, поэтому имя
/// показывается неразделённым: у краткого вида своё толкование имени.
const List<ColumnSpec> _briefColumns = [
  ColumnSpec(id: FsColumn.icon, width: 0, pinned: true),
  ColumnSpec(id: FsColumn.name, width: 0, pinned: true),
];
