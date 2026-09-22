import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'cursor_pin.dart';
import 'file_table_header.dart';
import 'panel_drag.dart';
import 'panels_settings.dart';
import 'columns.dart';
import 'file_table_row.dart';
import 'mark_drag.dart';
import 'row_cache.dart';

/// Таблица файлов: заголовки колонок, вертикальные линейки на всю высоту и
/// прокручиваемый список строк.
class FileTable extends StatefulWidget {
  const FileTable({super.key, required this.panel, required this.settings});

  final Session panel;

  /// Настройки видов — спрашиваются в момент подмотки, а не при сборке: снятый
  /// в окне настроек флажок действует сразу.
  final PanelsSettings Function() settings;

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
  String? _scrolledDirectory;

  /// Высота видимой части списка и высота строки из последней разметки: по ним
  /// считается, докуда прокручивать новый список ещё до того, как он появится.
  double _listHeight = 0;
  double _rowHeight = 0;

  /// Высота строки заголовков: от неё считается, какая строка под курсором при
  /// перетаскивании. Запоминается там же, где и остальные размеры, — при
  /// разметке.
  double _headerHeight = 0;

  int _lastCursorIndex = -1;

  /// Готовые строки: та же строка отдаётся тем же виджетом (`row_cache.dart`).
  final RowCache _cache = RowCache();

  /// Посчитанные ширины и то, из чего они посчитаны.
  ///
  /// Не ради самого счёта — он дешёвый, — а ради примет: новый список ширин на
  /// каждую сборку означал бы, что ни одна строка не совпала сама с собой
  /// (`docs/spec/panel-redraw.md`, §7).
  List<double>? _widths;
  List<ColumnSpec>? _widthsOf;
  double _widthsFor = -1;
  double _widthsIcon = -1;

  /// Строка под курсором с прошлого показа — чтобы перестановка её не сдвинула.
  final CursorPin _pin = CursorPin();

  int _lastTapIndex = -1;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Пометка правой кнопкой — жест общий со всеми видами
  /// (`spec/mouse-marking.md`).
  late final MarkDrag _marking = MarkDrag(
    panel: widget.panel,
    indexAt: _indexAt,
    indexNear: _rowUnder,
    bounds: () => (_headerHeight, _headerHeight + _listHeight),
    scroll: () => _scroll,
    activate: () => AppScope.read(context).activate(widget.panel),
  );

  @override
  void initState() {
    super.initState();
    widget.panel.addListener(_onPanelChanged);
    _askRows();
  }

  @override
  void didUpdateWidget(FileTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel != widget.panel) {
      oldWidget.panel.removeListener(_onPanelChanged);
      widget.panel.addListener(_onPanelChanged);
      _askRows();
    }
  }

  @override
  void dispose() {
    _marking.dispose();
    widget.panel.removeListener(_onPanelChanged);
    _scroll.dispose();
    super.dispose();
  }

  /// Строки, которые вид **просил**: содержимое каталога.
  ///
  /// Пока ядро не ответило на просьбу (`showRows`), в панели лежит набор
  /// прежнего вида — древесный. Рисовать его таблицей нельзя: живьём при
  /// переключении с дерева на миг показывался список ветвей, и только потом
  /// он сменялся содержимым каталога (`docs/spec/panel-node-list.md`, §3).
  List<FileEntry> get _rows => widget.panel.rows == RowsKind.listing ? widget.panel.entries : const [];

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

  void _onPanelChanged() {
    final panel = widget.panel;
    if (panel.currentPath != _scrolledDirectory) {
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
    if (panel.currentPath == _scrolledDirectory) {
      return;
    }

    final previous = _scroll;
    // Вид собрали заново — после полноэкранного просмотра или перезапуска:
    // список встаёт туда, где стоял, а не подматывается к курсору заново.
    // Подмотка ставила курсор у нижнего края, и человек находил его не там,
    // где оставил (`docs/spec/panel-views.md`, §10).
    final first = _scrolledDirectory == null;
    _scrolledDirectory = panel.currentPath;
    _lastCursorIndex = panel.cursorIndex;
    _scroll = ScrollController(initialScrollOffset: first ? panel.scrollOffset : _cursorOffset());

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
    final total = widget.panel.entries.length * _rowHeight;
    return (bottom - _listHeight).clamp(0.0, math.max(0.0, total - _listHeight));
  }

  /// Держит курсор в видимой части списка. Прокрутка мгновенная: в файловом
  /// менеджере анимация только мешает быстрому перебору клавишами.
  ///
  /// Перестановку списка — сортировкой или переименованием — курсор переживает
  /// **не двигаясь по экрану**: строка под ним уезжает на другое место, и вид
  /// уезжает вместе с ней (`docs/spec/panel-views.md`, §9).
  void _ensureCursorVisible() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    // Шаг строк — тот самый, которым размечен список: он зависит от размера
    // иконки (`FileIconSize.rowHeight`). Мерить прокрутку кеглем темы значило
    // бы промахиваться мимо курсора тем сильнее, чем крупнее иконки, — и на
    // живой проверке курсор уезжал за нижний край.
    final rowHeight = _rowHeight > 0 ? _rowHeight : FcTheme.of(context).metrics.rowHeight;
    final position = _scroll.position;
    final rows = widget.panel.entries;
    final at = widget.panel.cursorIndex;

    // Запоминается **всегда**, флажок или нет: иначе после выключения и
    // включения закрепление сработало бы от устаревшего места.
    final from = widget.settings().cursorHoldsPlace ? _pin.movedFrom(rows, at) : null;
    _pin.remember(rows, at);
    final base =
        from == null
            ? position.pixels
            : (position.pixels + (at - from) * rowHeight).clamp(position.minScrollExtent, position.maxScrollExtent);

    final top = at * rowHeight;
    final bottom = top + rowHeight;

    double? target;
    if (top < base) {
      target = top;
    } else if (bottom > base + position.viewportDimension) {
      target = bottom - position.viewportDimension;
    } else if (base != position.pixels) {
      target = base;
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
              // Размер иконки задаёт и высоту строки, и ширину колонки под
              // ней: величина одна, и считается она в одном месте, иначе
              // иконка вылезет из строки или в колонке останется дыра.
              final iconSize = FileIconSize.of(theme.metrics, app.fileIcons);
              // Поле справа принадлежит содержимому, а не подсветке строки:
              // `right="40"` у содержимого строки при рамке панели, идущей
              // до самого края.
              final inset = theme.metrics.panelRightPadding;
              final widths = _widthsOfColumns(columns, constraints.maxWidth - inset, iconSize, theme.metrics);
              final contentWidth = widths.fold<double>(0, (sum, width) => sum + width) + inset;

              // Сколько строк видно — от этого считается шаг PgUp/PgDn.
              final listHeight = constraints.maxHeight - theme.metrics.headerRowHeight;
              final rowHeight = FileIconSize.listRow(theme.metrics, app.fileIcons);
              panel.pageSize = (listHeight / rowHeight).floor().clamp(1, 1000);
              // Столбцов у таблицы нет: `Left`/`Right` достаются «в начало» и
              // «в конец» (`docs/spec/panel-views.md`, §10).
              panel.cursorSteps = const PanelSteps.list();
              // Те же размеры нужны прокрутке нового каталога, а она считается
              // до разметки: запоминаем то, что известно сейчас.
              // Область списка ужалась — курсор мог уехать под обрез. Так это
              // и бывает: строка состояния вырастает **из-за того**, что курсор
              // встал на длинное имя, и выталкивает нижние строки вниз
              // (`docs/widgets.md`, раздел `PanelStatusBar`).
              if (listHeight < _listHeight) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCursorVisible());
              }
              _listHeight = listHeight;
              _rowHeight = rowHeight;
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
                      sorted: panel.sorted,
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

              // Приём брошенного — общий на все виды: своё у таблицы только
              // геометрия (`panel_drag.dart`).
              return _withMarking(
                PanelDropArea(panel: panel, spotAt: _spotAt, highlightOf: _highlightOf, child: content),
              );
            },
          ),
    );
  }

  /// Пометка правой кнопкой поверх таблицы.
  ///
  /// Слой стоит **всегда**, а не появляется вместе с жестом: строение дерева
  /// посреди работы мышью меняться не вправе — на этом уже один раз
  /// погорели, и список тогда перематывался к началу
  /// (`spec/drag-and-drop.md`).
  Widget _withMarking(Widget content) {
    return Listener(
      onPointerDown: _marking.down,
      onPointerMove: _marking.move,
      onPointerUp: _marking.up,
      onPointerCancel: _marking.up,
      child: content,
    );
  }

  /// Что под курсором при перетаскивании — строка-каталог или сама панель.
  ///
  /// null означает «сюда нельзя», и это же гасит подсветку: человек видит отказ
  /// до того, как отпустит кнопку.
  DropSpot? _spotAt(Offset local) {
    final panel = widget.panel;
    if (panel.currentPath.isEmpty || !panel.source.canWrite) {
      return null;
    }
    final entry = _entryAt(local);
    // Бросок на строку-каталог кладёт **в неё**; на файл, на `..` и мимо строк
    // — в каталог, открытый в панели.
    if (entry != null && entry.isDirectory) {
      return DropSpot(destination: entry.path, entry: entry);
    }
    return DropSpot(destination: widget.panel.currentPath);
  }

  /// Строка под точкой — с поправкой на заголовки и прокрутку.
  FileEntry? _entryAt(Offset local) {
    final index = _indexAt(local);
    return index == null ? null : widget.panel.entries[index];
  }

  /// Номер строки под точкой; null — точка не на строке: выше списка
  /// (заголовки колонок) или ниже последней строки.
  int? _indexAt(Offset local) {
    if (_rowHeight <= 0 || local.dy < _headerHeight) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final index = ((local.dy - _headerHeight + offset) / _rowHeight).floor();
    return index >= 0 && index < widget.panel.entries.length ? index : null;
  }

  /// Что обвести: строку-каталог, в которую бросают; null — всю панель.
  Rect? _highlightOf(DropSpot spot) {
    final entry = spot.entry;
    final index = entry == null ? -1 : widget.panel.entries.indexOf(entry);
    if (index < 0) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    return Rect.fromLTWH(0, _headerHeight + index * _rowHeight - offset, double.infinity, _rowHeight);
  }

  Widget _buildList(List<ColumnSpec> columns, List<double> widths) {
    final panel = widget.panel;
    // Контроллер берётся из контекста таблицы, а не из контекста строки:
    // строки пересобираются, и к моменту обработки клика элемент строки
    // может быть уже отсоединён от дерева.
    final app = AppScope.read(context);

    return ListenableBuilder(
      // Строки перерисовываются и при движении курсора, и при изменении
      // пометки; ListView строит только видимые, поэтому это дёшево.
      listenable: panel,
      builder: (context, _) {
        _prepareScroll();

        // Ошибка чтения списка не убирает: не прочитался **новый** каталог, а
        // панель осталась в прежнем — с его содержимым, курсором и пометкой.
        // Стереть их значило бы отнять и `..`, и всё, чем отсюда уходят:
        // человек, ткнувшийся в чужой каталог, оказывался запертым в
        // сообщении. Про неудачу говорит строка состояния, и этого довольно.
        final rows = _rows;
        if (rows.isEmpty) {
          return const SizedBox.shrink();
        }

        // Курсор горит там, куда попадёт следующее нажатие, — и вопрос об
        // этом один на всё приложение, тот же, которым светится плашка. Своим
        // признаком активности панель отвечала на другой вопрос: ввод мог уйти
        // в список фоновых работ под ней, а курсор оставался гореть — как
        // будто стрелки всё ещё её.
        //
        // Спрашивается один раз на список, а не в каждой строке: ответ у них
        // общий, а обращение это поиск унаследованного виджета.
        final active = takesKeysHere(context, panel);
        // Тема — в приметах кадра: сменили её или размер значков, и прежние
        // строки нарисованы не теми цветами.
        final theme = FcTheme.of(context);
        // Правило показа имён одно на приложение: две панели, делящие имя
        // по-разному, — не гибкость, а недосмотр.
        final naming = app.fileNaming;
        _cache.frame([theme, columns, widths, rows, naming, _rowHeight]);

        return NotificationListener<ScrollEndNotification>(
          // Прокрутка запоминается, когда устоялась: с неё вид и начнёт, когда
          // его соберут заново — после полноэкранного просмотра или
          // перезапуска.
          //
          // Запоминается **всякая**, включая первую, которой список встаёт на
          // восстановленное место: если её прижало к краю (список короче, чем
          // был), то прижатое и есть новая правда.
          onNotification: (notification) {
            panel.setScrollOffset(notification.metrics.pixels);
            return false;
          },
          child: ListView.builder(
            // Новый каталог — новый список: положение прежнего в него не
            // переносится.
            key: ValueKey(_scrolledDirectory),
            controller: _scroll,
            // Тем же шагом, что и всё остальное: `_rowHeight` посчитан выше, в
            // разметке, и учитывает крупные иконки.
            itemExtent: _rowHeight,
            itemCount: rows.length,
            primary: false,
            // Беречь строке нечего: своего состояния у неё нет, а значок помнит
            // себя по пути и уезд с экрана переживает сам
            // (`docs/spec/panel-redraw.md`, §7).
            addAutomaticKeepAlives: false,
            itemBuilder: (context, index) {
              final entry = rows[index];
              final marked = panel.isMarked(entry);
              final underCursor = index == panel.cursorIndex;
              return _cache.of(index, [entry, marked, underCursor, active], () {
                final row = FileTableRow(
                  entry: entry,
                  columns: columns,
                  widths: widths,
                  marked: marked,
                  underCursor: underCursor,
                  panelActive: active,
                  naming: naming,
                  // Байты — для правил иконок по содержимому. Спрашивают их у
                  // панели: строка принадлежит ей, и она же знает, откуда читать.
                  contentOf: panel.contentOf,
                  onPress: () => _handleRowPress(app, index),
                );
                // Строку можно утащить наружу — если есть кому тащить.
                return panelDragSource(context: context, panel: panel, entry: entry, child: row);
              });
            },
          ),
        );
      },
    );
  }

  // --- Пометка правой кнопкой (`spec/mouse-marking.md`) ---

  /// Строка, к которой тянут: за краями списка — крайняя видимая, а не
  /// последняя в каталоге.
  ///
  /// Иначе указатель, ушедший за нижний край, помечал бы каталог до конца одним
  /// махом; а так отрезок растёт по мере того, как список едет.
  int _rowUnder(Offset local) {
    final bottom = _headerHeight + _listHeight;
    final dy = local.dy.clamp(_headerHeight, math.max(_headerHeight, bottom - 1));
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final index = ((dy - _headerHeight + offset) / _rowHeight).floor();
    return index.clamp(0, widget.panel.entries.length - 1);
  }

  /// Клик ставит курсор, двойной клик по той же строке — входит в объект.
  ///
  /// Двойной клик распознаётся вручную: штатный `onDoubleTap` заставляет
  /// Flutter придержать одиночный клик до истечения таймаута, а курсор в
  /// файловом менеджере должен переставляться сразу.
  void _handleRowPress(Application app, int index) {
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

  /// Ширины — теми же числами и тем же списком, пока считать их не из чего
  /// заново.
  List<double> _widthsOfColumns(List<ColumnSpec> columns, double available, double iconSize, FcMetrics metrics) {
    if (_widths case final ready?
        when identical(_widthsOf, columns) && available == _widthsFor && iconSize == _widthsIcon) {
      return ready;
    }
    _widthsOf = columns;
    _widthsFor = available;
    _widthsIcon = iconSize;
    return _widths = _columnWidths(columns, available, iconSize, metrics);
  }

  /// Фиксированные колонки получают свою ширину, «резиновая» — весь остаток.
  /// Если остатка не хватает, она сжимается до минимума, а таблица начинает
  /// прокручиваться по горизонтали.
  List<double> _columnWidths(List<ColumnSpec> columns, double available, double iconSize, FcMetrics metrics) {
    // Ширину закреплённых колонок задаёт приложение, а не файл настроек
    // (`models.md`), и у иконки она складывается из отступа, самой иконки и
    // просвета до имени — то есть из метрик темы, а не из константы раскладки.
    double widthOf(ColumnSpec column) =>
        column.id == FsColumns.icon ? FileIconSize.columnWidth(metrics, iconSize) : column.width;

    var fixed = 0.0;
    for (final column in columns) {
      if (!column.flexible) {
        fixed += widthOf(column);
      }
    }

    final rest = available - fixed;
    return [
      for (final column in columns)
        if (column.flexible) (rest < column.minWidth ? column.minWidth : rest) else widthOf(column),
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

  static const Set<String> _noLeftDivider = {FsColumns.icon, FsColumns.name, FsColumns.ext};

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

/// Рамка вокруг того, куда попадёт брошенное.
///
/// Рисунок, а не виджет с рамкой: подсветка появляется и гаснет посреди
/// перетаскивания, и менять ради неё строение дерева нельзя — список
/// пересобрался бы, а вместе с ним потерялась бы прокрутка.
