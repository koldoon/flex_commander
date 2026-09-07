import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_table_header.dart';
import 'file_type_icon.dart';
import 'panel_drag.dart';
import 'panels_settings.dart';

/// Дерево каталогов: где панель сейчас, что рядом и что внутри.
///
/// Спецификация — `docs/spec/panel-view-tree.md`; модель строк —
/// `docs/spec/panel-node-list.md`.
///
/// **Своей модели у вида нет.** Строки собирает ядро: оно же держит раскрытое,
/// глубину и порядок, а курсор и пометка здесь те же, что у списка. Раньше
/// дерево держало ветви у себя и водило панель за собой — отсюда вышел целый
/// класс гонок, который чинился шесть заходов подряд.
class TreeView extends StatefulWidget {
  const TreeView({super.key, required this.panel, required this.settings});

  /// Имя вида — оно же ключ настройки панели.
  static const String viewId = 'tree';

  final Panel panel;

  /// Настройки видов: показывать ли размер. Способом узнать, а не значением —
  /// флажок правят в окне выбора вида, и следующий же кадр обязан его учесть.
  final PanelsSettings Function() settings;

  @override
  State<TreeView> createState() => TreeViewState();
}

class TreeViewState extends State<TreeView> {
  final ScrollController _scroll = ScrollController();

  /// Окно, в пределах которого два щелчка по одной строке считаются двойным.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  int _lastTapIndex = -1;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Высота строки вместе с просветом; 0 — разметки ещё не было.
  double _step = 0;

  /// Высота шапки: она входит в область, но не в список, и попадание броском
  /// считается от первой строки, а не от верха области.
  double _headerHeight = 0;

  /// Куда бросили: ветвь раскрывается сразу, а перечитывается, когда работа
  /// кончится (`docs/spec/drag-and-drop.md`, §4).
  String? _dropped;

  /// Работа после броска и правда началась: без этого первая же кончившаяся
  /// чужая работа перечитала бы дерево впустую.
  bool _sawWork = false;

  Operations? _operations;

  /// Строка, к которой прокручивали, и строки, в которых её искали.
  ///
  /// Следить надо за обоими: строки приходят позже курсора — при запуске
  /// сначала список каталога, потом дерево, — и подмотка, сделанная по прежним
  /// строкам, оставляет курсор за краем.
  int _shownCursor = -1;
  List<FileEntry>? _shownRows;

  /// Сохранённую прокрутку уже поставили.
  ///
  /// Признак тратится не на первом кадре, а тогда, когда её и правда есть куда
  /// ставить: строки стали древесными и список измерен. Живьём иначе выходило
  /// «через раз» — на первом кадре строки ещё списочные, и восстанавливать
  /// было нечего.
  bool _restored = false;

  /// Сколько кадров ждём список: он появляется не в том же кадре, что вид.
  int _restoreTries = 0;

  @override
  void initState() {
    super.initState();
    // Вид говорит, что ему нужно; собирать строки — дело ядра
    // (`docs/spec/panel-node-list.md`, §3).
    unawaited(widget.panel.showRows(RowsKind.tree));
    // Ждать строк начинаем сразу: они приходят позже вида, а восстановление
    // прокрутки без них смысла не имеет.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _revealCursor();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Работы слушаются ради брошенного: каталог раскрыт сразу, а появившееся в
    // нём видно только после перечитывания.
    final operations = AppScope.read(context).operations;
    if (identical(operations, _operations)) {
      return;
    }
    _operations?.removeListener(_onOperations);
    _operations = operations..addListener(_onOperations);
  }

  @override
  void dispose() {
    _operations?.removeListener(_onOperations);
    _scroll.dispose();
    super.dispose();
  }

  /// Работа кончилась — перечитать дерево: в каталоге появилось или исчезло.
  void _onOperations() {
    if (_dropped == null) {
      return;
    }
    if (_operations?.all.isNotEmpty ?? false) {
      _sawWork = true;
      return;
    }
    if (!_sawWork) {
      return;
    }
    _dropped = null;
    _sawWork = false;
    unawaited(widget.panel.reload());
  }

  List<FileEntry> get _rows => widget.panel.entries;

  /// Прокрутить к курсору, если он ушёл из виду.
  ///
  /// Список стоит **целыми строками**: высота области на шаг строки делится
  /// редко, и подмотка «ровно настолько, чтобы влезло» оставляла бы строку
  /// разрезанной нижним краем.
  ///
  /// [restoring] — первый показ после восстановления. Вид встаёт туда, где
  /// стоял при закрытии, и правила ниже нужны, только если это не подошло:
  /// пока приложение было закрыто, снаружи могло измениться, и курсор
  /// оказывается за краем. Правил два (`panel-view-tree.md`, §5): помещается
  /// ветвь вместе с курсором — она и становится первой строкой, и видно,
  /// **откуда** этот курсор; не помещается — курсор уводится к середине.
  void _revealCursor() {
    final rows = _rows;
    final at = widget.panel.cursorIndex;
    final ready = _scroll.hasClients && _step > 0 && at >= 0 && at < rows.length;

    // Восстановление ждёт своего кадра: строки при запуске приходят позже
    // вида, и признак тратить рано.
    final restoring = !_restored && widget.panel.rows == RowsKind.tree;
    if (!ready || (!_restored && !restoring)) {
      if (!_restored && _restoreTries < _restoreLimit) {
        _restoreTries++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _revealCursor();
          }
        });
      }
      return;
    }
    if (restoring) {
      _restored = true;
    }

    final height = _scroll.position.viewportDimension;
    // Целых строк в области; последняя, разрезанная, за строку не считается.
    final visible = (height / _step).floor().clamp(1, rows.length);
    final maxFirst = (rows.length - visible).clamp(0, rows.length);

    var first = (_scroll.offset / _step).round();

    if (restoring) {
      // Сначала — туда, где вид стоял при закрытии.
      first = (widget.panel.scrollOffset / _step).round().clamp(0, maxFirst);

      if (at < first || at > first + visible - 1) {
        // Не подошло: пока приложение было закрыто, снаружи изменилось.
        final parent = _parentIndexOf(at);
        first = parent >= 0 && at - parent < visible - 1 ? parent : at - visible ~/ 2;
      }
    }

    // Курсор обязан быть виден целиком, каким бы ни было правило.
    first = first.clamp(0, maxFirst);
    if (at < first) {
      first = at;
    } else if (at > first + visible - 1) {
      first = at - visible + 1;
    }

    // Предел считается по своим строкам, а не спрашивается у списка: строки
    // только что сменились, и его мерки ещё от прежних — подмотка вышла бы на
    // строку короче, и курсор остался бы под нижним краем.
    final limit = (rows.length * _step - height).clamp(0.0, double.infinity);
    final target = (first * _step).clamp(0.0, limit);
    if (target != _scroll.offset) {
      _scroll.jumpTo(target);
    }
  }

  /// Сколько кадров ждать строк, прежде чем махнуть рукой.
  static const int _restoreLimit = 20;

  /// Строка ветви, в которой лежит строка [at]; -1 — такой нет.
  int _parentIndexOf(int at) {
    final rows = _rows;
    for (var i = at - 1; i >= 0; i--) {
      if (rows[i].level < rows[at].level) {
        return i;
      }
    }
    return -1;
  }

  /// Строка под точкой — в местных координатах области.
  FileEntry? _rowUnder(Offset local) {
    if (_step <= 0 || local.dy < _headerHeight) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final index = ((local.dy - _headerHeight + offset) / _step).floor();
    final rows = _rows;
    return index >= 0 && index < rows.length ? rows[index] : null;
  }

  /// Куда попадёт брошенное: в каталог под указателем, а указали на файл — в
  /// тот, где он лежит.
  ///
  /// В дереве каталогов видно много разом, и «каталог панели» тут — случайное
  /// место, где стоит курсор. Поэтому мимо ветвей бросать некуда: подсветки
  /// нет, отпускание ничего не делает (`docs/spec/drag-and-drop.md`, §4).
  DropSpot? _spotAt(Offset local) {
    final panel = widget.panel;
    if (!panel.source.canWrite) {
      return null;
    }
    final under = _rowUnder(local);
    if (under == null) {
      return null;
    }
    if (under.isDirectory) {
      return DropSpot(destination: under.path, entry: under);
    }
    final parent = _parentOf(under);
    return parent == null ? null : DropSpot(destination: parent.path, entry: parent);
  }

  /// Ветвь, в которой лежит эта строка: ближайшая выше с меньшей глубиной.
  ///
  /// По глубине, а не по пути: строки уже разложены деревом, и соседство в
  /// списке и есть родство.
  FileEntry? _parentOf(FileEntry row) {
    final at = _parentIndexOf(_rows.indexOf(row));
    return at < 0 ? null : _rows[at];
  }

  /// Обводится **та ветвь, в которую ляжет**: указали на файл — горит его
  /// каталог, и видно, куда именно попадёт брошенное.
  Rect? _highlightOf(DropSpot spot) {
    final at = _rows.indexWhere((row) => row.path == spot.destination);
    if (at < 0 || _step <= 0) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    return Rect.fromLTWH(0, _headerHeight + at * _step - offset, double.infinity, _step);
  }

  /// Бросили — раскрываем: в закрытую ветвь файл уедет молча, и человек не
  /// увидит, что он там появился.
  void _onDropped(DropSpot spot) {
    _dropped = spot.destination;
    _sawWork = false;
    widget.panel.setExpanded(spot.destination, expanded: true);
  }

  /// Щелчок ставит курсор, двойной — раскрывает ветвь или сворачивает её.
  ///
  /// То же, что делает `Enter`: вид со своей навигацией обязан отвечать и на
  /// двойной щелчок (`docs/spec/panel-views.md`, §9). Распознаётся вручную —
  /// как в таблице: штатный `onDoubleTap` заставляет ждать окно двойного
  /// щелчка перед **первым**, и курсор начинает опаздывать.
  void _onTap(int index) {
    final now = DateTime.now();
    final again = index == _lastTapIndex && now.difference(_lastTapTime) < _doubleTapWindow;
    _lastTapIndex = index;
    _lastTapTime = now;

    AppScope.read(context).activate(widget.panel);
    widget.panel.setCursorIndex(index);
    if (again) {
      toggleAt(index);
    }
  }

  /// Раскрыть строку или свернуть её обратно.
  void toggleAt(int index) {
    final rows = _rows;
    if (index < 0 || index >= rows.length) {
      return;
    }
    final row = rows[index];
    if (!row.isDirectory) {
      return;
    }
    widget.panel.setExpanded(row.path, expanded: !row.isOpen);
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: panel,
      builder: (context, _) {
        // Столбцов у дерева нет: `Left` и `Right` здесь свои
        // (`docs/spec/panel-view-tree.md`, §6).
        panel.columnRows = 0;

        final app = AppScope.read(context);
        // Шаг строки — тот же, что в списке: панели стоят рядом, и строки
        // обязаны сходиться. Считается он одним местом на оба вида
        // (`FileIconSize.listRow`), иначе значок настроят покрупнее — и
        // разъедутся (`docs/spec/panel-view-tree.md`, §4).
        final step = FileIconSize.listRow(theme.metrics, app.fileIcons);
        _step = step;
        _headerHeight = theme.metrics.headerRowHeight;

        // Колонки те же, что у таблицы, и ширина у размера та же: дерево
        // показывает то же самое, и мерить это другой меркой незачем.
        final showSize = widget.settings().treeSize;
        final sizeWidth = _sizeColumn.width;
        // Поле справа принадлежит содержимому, а не подсветке строки, — как и
        // в таблице.
        final inset = theme.metrics.panelRightPadding;

        final rows = _rows;
        if (panel.cursorIndex != _shownCursor || !identical(rows, _shownRows)) {
          _shownCursor = panel.cursorIndex;
          _shownRows = rows;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _revealCursor();
            }
          });
        }

        final list = NotificationListener<ScrollEndNotification>(
          // Прокрутка запоминается, когда устоялась, — и только тогда:
          // сообщение на каждую точку было бы лентой сообщений через границу.
          onNotification: (notification) {
            panel.setScrollOffset(notification.metrics.pixels);
            return false;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Страница — то, что видно: тем же счётом, что в таблице.
              panel.pageSize = (constraints.maxHeight / step).floor().clamp(1, 1000);
              return ListView.builder(
                controller: _scroll,
                itemExtent: step,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final branch = _BranchRow(
                    row: row,
                    underCursor: index == panel.cursorIndex,
                    marked: panel.isMarked(row),
                    // Размер приходит **в строке**: его проставило ядро, и
                    // второго источника у него нет (`panel-node-list.md`, §4).
                    size: showSize ? row.size : FileEntry.unknownSize,
                    sizeWidth: showSize ? sizeWidth : 0,
                    inset: inset,
                    panelActive: app.view.takesKeys(panel),
                    onTap: () => _onTap(index),
                    onToggle: () {
                      app.activate(panel);
                      toggleAt(index);
                    },
                  );
                  // Тянут за ветвь то же, что тянут за строку списка: объект, а
                  // не картинку (`panel_drag.dart`).
                  return panelDragSource(context: context, panel: panel, entry: row, child: branch);
                },
              );
            },
          ),
        );

        final content = Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_TreeHeader(showSize: showSize, sizeWidth: sizeWidth, inset: inset), Expanded(child: list)],
            ),
            // Линейка идёт от шапки и поверх строк — как в таблице, где она
            // объявлена после списка, чтобы подсветка курсора её не закрывала.
            if (showSize)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SizeDividerPainter(
                      right: sizeWidth + inset,
                      color: theme.colors.columnDivider,
                      inset: theme.metrics.strokeWidth,
                    ),
                  ),
                ),
              ),
          ],
        );

        // Бросают в каталог под указателем, а не в каталог панели: дерево
        // показывает много каталогов разом.
        return PanelDropArea(
          panel: panel,
          spotAt: _spotAt,
          highlightOf: _highlightOf,
          onDropped: _onDropped,
          child: content,
        );
      },
    );
  }
}

/// Колонки дерева: сама ветвь и размер.
///
/// Те же `ColumnSpec`, что у таблицы, и та же ширина у размера: дерево
/// показывает то же самое, и мерить это другой меркой незачем. Здесь их две; с
/// датой станет три (`docs/spec/panel-view-tree.md`, §4).
const ColumnSpec _treeColumn = ColumnSpec(id: FsColumn.tree, width: 0, pinned: true);
const ColumnSpec _sizeColumn = ColumnSpec(id: FsColumn.size, width: 64, align: ColumnAlign.end);

/// Шапка дерева: те же заголовки, что у таблицы.
///
/// Своя, а не `FileTableHeader`: у того три жеста — сортировка, перестановка
/// колонок и тяга ширины, — и все три дереву обещать нечем. Ячейка при этом та
/// же самая, чтобы набор и середина совпадали до точки.
class _TreeHeader extends StatelessWidget {
  const _TreeHeader({required this.showSize, required this.sizeWidth, required this.inset});

  final bool showSize;
  final double sizeWidth;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    return SizedBox(
      height: theme.metrics.headerRowHeight,
      child: Row(
        children: [
          const Expanded(
            child: FileTableHeaderCell(column: _treeColumn, sorted: false, direction: SortDirection.ascending),
          ),
          if (showSize)
            SizedBox(
              width: sizeWidth,
              child: const FileTableHeaderCell(column: _sizeColumn, sorted: false, direction: SortDirection.ascending),
            ),
          SizedBox(width: inset),
        ],
      ),
    );
  }
}

/// Линейка слева от колонки размера.
///
/// Одна на всё дерево: колонок здесь две, и разделять больше нечего. Не доходит
/// до низа на толщину линии — по той же причине, что в таблице: сойдись она с
/// линейкой над строкой состояния, получился бы перекрёсток, и глаз читал бы
/// его как рамку, которой нет.
class _SizeDividerPainter extends CustomPainter {
  const _SizeDividerPainter({required this.right, required this.color, required this.inset});

  final double right;
  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width - right;
    canvas.drawRect(Rect.fromLTWH(x, 0, inset, size.height - inset), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SizeDividerPainter old) => old.right != right || old.color != color || old.inset != inset;
}

/// Строка дерева: знак раскрытия, значок, имя и размер.
class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.row,
    required this.underCursor,
    required this.marked,
    required this.size,
    required this.sizeWidth,
    required this.inset,
    required this.panelActive,
    required this.onTap,
    required this.onToggle,
  });

  /// Строка вида: глубина и раскрытость проставлены ядром
  /// (`docs/spec/panel-node-list.md`, §4).
  final FileEntry row;

  final bool underCursor;

  /// Помечена ли ветвь. Показывается теми же цветами, что в списке: пометка в
  /// панели одна, и выглядеть она обязана одинаково
  /// (`docs/spec/panel-view-tree.md`, §7).
  final bool marked;

  /// Размер объекта; [FileEntry.unknownSize] — показывать нечего: у каталога
  /// его ещё не считали, а колонку могли и выключить.
  final int size;

  /// Ширина колонки размера и поле справа — те же, что у шапки: колонка на то и
  /// колонка, чтобы числа стояли под своим заголовком.
  final double sizeWidth;
  final double inset;

  final bool panelActive;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  bool get _selected => underCursor && panelActive;

  /// Знак раскрытия: у каталога — шеврон, у файла ничего.
  ///
  /// Пусто, а не пропущенный квадрат: имена ветвей одного уровня начинаются с
  /// одной вертикали независимо от того, есть внутри что-нибудь или нет
  /// (`docs/spec/panel-view-tree.md`, §4).
  String _mark(FcIcons icons) {
    if (!row.isDirectory) {
      return '';
    }
    return String.fromCharCode(row.isOpen ? icons.branchOpen.codePoint : icons.branchClosed.codePoint);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    final icons = theme.icons;

    // Знак раскрытия занимает **тот же квадрат**, что значок объекта, и отбит
    // от него на `treeMarkGap`. Отсюда и шаг вглубь — квадрат вместе с этим
    // просветом: знак дочерней ветви приходится серединой на середину значка
    // родительской (`docs/spec/panel-view-tree.md`, §4).
    final square = FileIconSize.of(metrics, AppScope.read(context).fileIcons);
    final indent = square + metrics.treeMarkGap;

    final style = _selected ? theme.rowStyle.copyWith(color: colors.cursorText) : theme.rowStyle;
    final glyph = TextStyle(
      fontFamily: icons.fontFamily,
      fontSize: metrics.fontSize,
      color: _selected ? colors.iconSelected : colors.icon,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(bottom: metrics.rowGap),
        child: DecoratedBox(
          // Слоями снизу вверх, как в списке: обычная → помеченная → под
          // курсором (`FileTableRow`).
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
              Padding(
                // Слева — то же поле, что у строки списка: панели рядом, и их
                // содержимое обязано начинаться на одной вертикали.
                padding: EdgeInsets.only(left: metrics.iconLeftPadding + row.level * indent),
                // Те же две поправки, что у строки списка: содержимое опущено
                // относительно подсветки, а имя — относительно значка. Панели
                // стоят рядом, и строка дерева обязана совпадать со строкой
                // списка до точки.
                child: Transform.translate(
                  offset: Offset(0, metrics.rowContentVerticalNudge),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggle,
                        child: SizedBox(
                          width: square,
                          // По середине квадрата, а не по левому его краю: глиф
                          // угла узкий, и прижатый влево он отходил бы от значка
                          // на полквадрата.
                          child: Center(child: Text(_mark(icons), style: glyph)),
                        ),
                      ),
                      SizedBox(width: metrics.treeMarkGap),
                      // Значок тот же, что в списке: у каталога папка, у файла
                      // его собственный — правило одно на приложение
                      // (`docs/spec/file-icons.md`).
                      FileTypeIcon(entry: row, selected: _selected),
                      SizedBox(width: metrics.iconGap),
                      Expanded(
                        child: Transform.translate(
                          offset: Offset(0, metrics.rowTextVerticalNudge),
                          child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                        ),
                      ),
                      // Колонка размера — своей ширины и под своим заголовком:
                      // число прижато к правому её краю, как в таблице.
                      if (sizeWidth > 0)
                        SizedBox(
                          width: sizeWidth,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding),
                            child: Transform.translate(
                              offset: Offset(0, metrics.rowTextVerticalNudge),
                              child: Text(formatSize(size), maxLines: 1, textAlign: TextAlign.right, style: style),
                            ),
                          ),
                        ),
                      SizedBox(width: inset),
                    ],
                  ),
                ),
              ),
              // Полоса пометки поверх фона: она должна читаться и тогда, когда
              // ветвь вдобавок под курсором.
              if (marked)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: metrics.markedBarWidth,
                  child: ColoredBox(color: colors.markedBar),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
