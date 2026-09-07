import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'cursor_pin.dart';
import 'file_table_header.dart';
import 'panel_drag.dart';
import 'panels_settings.dart';
import 'file_table_row.dart';

/// Таблица файлов: заголовки колонок, вертикальные линейки на всю высоту и
/// прокручиваемый список строк.
class FileTable extends StatefulWidget {
  const FileTable({super.key, required this.panel, required this.settings});

  final Panel panel;

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

  /// Строка под курсором с прошлого показа — чтобы перестановка её не сдвинула.
  final CursorPin _pin = CursorPin();

  int _lastTapIndex = -1;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Пометка правой кнопкой: строка, с которой жест начался; -1 — жеста нет.
  int _markAnchor = -1;

  /// Докуда дотянули в прошлый раз: строки за отрезком нужно вернуть в прежнее
  /// состояние, а знать, какие именно, можно только помня прошлый конец.
  int _markTo = -1;

  /// Помечаем или снимаем — решает первая строка жеста.
  bool _markAdds = true;

  /// Пометка, какой она была до жеста: по ней восстанавливаются строки,
  /// выпавшие из отрезка при ходе назад.
  Set<String> _markBefore = const {};

  /// Где указатель сейчас — нужно автопрокрутке: она едет по таймеру, а не по
  /// движениям, и своей координаты у неё нет.
  Offset _markPointer = Offset.zero;

  Timer? _markScroll;

  @override
  void initState() {
    super.initState();
    widget.panel.addListener(_onPanelChanged);
    // Вид говорит, что ему нужно: строки каталога. Молчание значило бы «сойдёт
    // и то, что дали», а дали бы то, что просил прежний вид, — дерево
    // (`docs/spec/panel-node-list.md`, §3).
    unawaited(widget.panel.showRows(RowsKind.listing));
  }

  @override
  void didUpdateWidget(FileTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel != widget.panel) {
      oldWidget.panel.removeListener(_onPanelChanged);
      widget.panel.addListener(_onPanelChanged);
      unawaited(widget.panel.showRows(RowsKind.listing));
    }
  }

  @override
  void dispose() {
    _markScroll?.cancel();
    widget.panel.removeListener(_onPanelChanged);
    _scroll.dispose();
    super.dispose();
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
    _scrolledDirectory = panel.currentPath;
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
              final widths = _columnWidths(columns, constraints.maxWidth - inset, iconSize, theme.metrics);
              final contentWidth = widths.fold<double>(0, (sum, width) => sum + width) + inset;

              // Сколько строк видно — от этого считается шаг PgUp/PgDn.
              final listHeight = constraints.maxHeight - theme.metrics.headerRowHeight;
              final rowHeight = FileIconSize.listRow(theme.metrics, app.fileIcons);
              panel.pageSize = (listHeight / rowHeight).floor().clamp(1, 1000);
              // Столбцов у таблицы нет: `Left`/`Right` достаются «в начало» и
              // «в конец» (`docs/spec/panel-views.md`, §10).
              panel.columnRows = 0;
              // Те же размеры нужны прокрутке нового каталога, а она считается
              // до разметки: запоминаем то, что известно сейчас.
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
                      onColumnTap: (column) {
                        app.activate(panel);
                        panel.sortBy(column);
                      },
                      // Колонки правятся, только когда они панельные: у
                      // списка находок раскладку просит источник, и менять в
                      // ней нечего — уйдёт она вместе с ним.
                      onLayoutChanged:
                          panel.source.columns != null
                              ? null
                              : (layout) {
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
      onPointerDown: _markDown,
      onPointerMove: _markMove,
      onPointerUp: _markUp,
      onPointerCancel: _markUp,
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
        if (panel.entries.isEmpty) {
          return const SizedBox.shrink();
        }

        return ListView.builder(
          // Новый каталог — новый список: положение прежнего в него не
          // переносится.
          key: ValueKey(_scrolledDirectory),
          controller: _scroll,
          // Тем же шагом, что и всё остальное: `_rowHeight` посчитан выше, в
          // разметке, и учитывает крупные иконки.
          itemExtent: _rowHeight,
          itemCount: panel.entries.length,
          primary: false,
          itemBuilder: (context, index) {
            final entry = panel.entries[index];
            final row = FileTableRow(
              entry: entry,
              columns: columns,
              widths: widths,
              marked: panel.isMarked(entry),
              underCursor: index == panel.cursorIndex,
              // Курсор горит там, куда попадёт следующее нажатие, — и вопрос
              // об этом один на всё приложение, тот же, которым светится
              // плашка. Своим признаком активности панель отвечала на другой
              // вопрос: ввод мог уйти в список фоновых работ под ней, а курсор
              // оставался гореть — как будто стрелки всё ещё её.
              panelActive: app.view.takesKeys(panel),
              // Правило показа одно на приложение: две панели, делящие имя
              // по-разному, — не гибкость, а недосмотр.
              naming: app.fileNaming,
              // Байты — для правил иконок по содержимому. Спрашивают их у
              // панели: строка принадлежит ей, и она же знает, откуда читать.
              contentOf: panel.contentOf,
              onTap: () => _handleRowTap(app, index),
            );
            // Строку можно утащить наружу — если есть кому тащить.
            return panelDragSource(context: context, panel: panel, entry: entry, child: row);
          },
        );
      },
    );
  }

  // --- Пометка правой кнопкой (`spec/mouse-marking.md`) ---

  /// Насколько далеко за краем список едет с наибольшей скоростью.
  static const double _autoScrollReach = 120;

  /// Наибольший шаг автопрокрутки за такт.
  static const double _autoScrollStep = 24;

  static const Duration _autoScrollTick = Duration(milliseconds: 16);

  /// Начало жеста: запоминаем строку, снимок пометки и направление.
  ///
  /// Направление задаёт первая строка: начали с непомеченной — весь отрезок
  /// помечается, начали с помеченной — снимается. Отдельной ветки «просто
  /// щелчок» нет: он и есть отрезок длиной в одну строку.
  void _markDown(PointerDownEvent event) {
    if (!_isMarking(event.kind, event.buttons)) {
      return;
    }
    // Начаться жест может только на строке: над заголовками колонок правая
    // кнопка по-прежнему открывает меню видимости.
    final index = _indexAt(event.localPosition);
    if (index == null) {
      return;
    }

    final panel = widget.panel;
    AppScope.read(context).activate(panel);

    _markAnchor = index;
    _markTo = index;
    _markBefore = panel.markedPaths;
    _markAdds = !panel.isMarked(panel.entries[index]);
    _markPointer = event.localPosition;
    _markSegment(index);
  }

  void _markMove(PointerMoveEvent event) {
    if (_markAnchor < 0 || !_isMarking(event.kind, event.buttons)) {
      return;
    }
    _markPointer = event.localPosition;
    _markSegment(_rowUnder(event.localPosition));
    _autoScroll(event.localPosition);
  }

  void _markUp(PointerEvent event) {
    _markAnchor = -1;
    _markBefore = const {};
    _markScroll?.cancel();
    _markScroll = null;
  }

  /// Жест — это правая кнопка, чем бы её ни нажали.
  ///
  /// Устройство не проверяется: протянуть с зажатой правой на трекпаде и так
  /// невозможно (правый щелчок там — двухпальцевый тап), а переключить пометку
  /// одной строки им можно, и запрещать это незачем.
  static bool _isMarking(PointerDeviceKind kind, int buttons) => buttons == kSecondaryMouseButton;

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

  /// Приводит к нужному виду отрезок от начальной строки до [to], а всё, что
  /// из отрезка выпало, возвращает в состояние до жеста.
  ///
  /// Отрезок, а не след: ход назад снимает то, что жест сам же и пометил.
  void _markSegment(int to) {
    final panel = widget.panel;
    final entries = panel.entries;
    final from = _markAnchor;

    final low = math.min(from, math.min(to, _markTo));
    final high = math.max(from, math.max(to, _markTo));
    final segmentLow = math.min(from, to);
    final segmentHigh = math.max(from, to);

    // Пометка меняется одной просьбой на весь отрезок: до ядра она едет
    // путями, и слать по сообщению на строку значило бы гнать сотню
    // сообщений за один взмах мыши.
    final marked = {...panel.markedPaths};
    for (var i = low; i <= high; i++) {
      final entry = entries[i];
      // «..» не помечается никогда — это правило самой пометки, и жесту
      // достаточно его не обходить.
      if (entry.isParent) {
        continue;
      }
      final wanted = i >= segmentLow && i <= segmentHigh ? _markAdds : _markBefore.contains(entry.path);
      if (wanted) {
        marked.add(entry.path);
      } else {
        marked.remove(entry.path);
      }
    }
    panel.setMarks(marked);

    _markTo = to;
    // Курсор идёт за жестом: иначе после пометки полутора экранов он остаётся
    // там, где его забыли, и следующая клавиша делает не то, что человек видит.
    panel.setCursorIndex(to);
  }

  /// У краёв список едет сам — иначе жестом нельзя пометить больше экрана.
  ///
  /// Скорость растёт с тем, насколько далеко указатель ушёл за край: одна
  /// скорость на все случаи либо мучительна на длинном списке, либо
  /// проскакивает нужное место. Шаг делается по таймеру, а не по движениям
  /// мыши: остановленную за краем руку список обязан слушаться дальше.
  void _autoScroll(Offset local) {
    final top = _headerHeight;
    final bottom = _headerHeight + _listHeight;

    var over = 0.0;
    if (local.dy < top) {
      over = local.dy - top;
    } else if (local.dy > bottom) {
      over = local.dy - bottom;
    }

    if (over == 0) {
      _markScroll?.cancel();
      _markScroll = null;
      return;
    }
    _markScroll ??= Timer.periodic(_autoScrollTick, (_) => _autoScrollStepped());
  }

  void _autoScrollStepped() {
    if (_markAnchor < 0 || !_scroll.hasClients) {
      return;
    }
    final top = _headerHeight;
    final bottom = _headerHeight + _listHeight;
    final dy = _markPointer.dy;
    final over = dy < top ? dy - top : (dy > bottom ? dy - bottom : 0.0);
    if (over == 0) {
      return;
    }

    final speed = (over.abs() / _autoScrollReach).clamp(0.0, 1.0) * _autoScrollStep;
    final position = _scroll.position;
    final target = (position.pixels + (over < 0 ? -speed : speed)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      return;
    }
    _scroll.jumpTo(target);
    _markSegment(_rowUnder(_markPointer));
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
  List<double> _columnWidths(List<ColumnSpec> columns, double available, double iconSize, FcMetrics metrics) {
    // Ширину закреплённых колонок задаёт приложение, а не файл настроек
    // (`models.md`), и у иконки она складывается из отступа, самой иконки и
    // просвета до имени — то есть из метрик темы, а не из константы раскладки.
    double widthOf(ColumnSpec column) =>
        column.id == FsColumn.icon ? FileIconSize.columnWidth(metrics, iconSize) : column.width;

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

/// Рамка вокруг того, куда попадёт брошенное.
///
/// Рисунок, а не виджет с рамкой: подсветка появляется и гаснет посреди
/// перетаскивания, и менять ради неё строение дерева нельзя — список
/// пересобрался бы, а вместе с ним потерялась бы прокрутка.
