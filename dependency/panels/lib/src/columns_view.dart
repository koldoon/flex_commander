import 'dart:async';
import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'column_chain.dart';
import 'file_type_icon.dart';
import 'mark_drag.dart';
import 'panels_settings.dart';

/// Столбцы, как в Finder: пройденный путь слева направо.
///
/// Спецификация — `docs/spec/panel-view-columns.md`; нарезка строк —
/// `column_chain.dart`.
///
/// **Своей модели у вида нет**, как и у дерева: строки собирает ядро
/// (`RowsKind.tree`), а вид их только нарезает столбцами. Курсор — панельный, и
/// второго места, где он якобы стоит, здесь нет: и столбец, и строка в нём
/// выводятся из `panel.cursorIndex`.
class ColumnsView extends StatefulWidget {
  const ColumnsView({super.key, required this.panel, required this.settings, required this.save});

  /// Имя вида — оно же ключ настройки панели.
  static const String viewId = 'columns';

  /// Сколько курсор стоит на закрытом каталоге, прежде чем вид его раскроет.
  ///
  /// Иначе ходьба стрелками показывала бы содержимое только после явного
  /// `Right`, и вид перестал бы отвечать на свой вопрос — «чем это окружено».
  static const Duration holdBeforeOpen = Duration(milliseconds: 150);

  final Session panel;

  /// Настройки видов: ширина столбца. Способом узнать, а не значением —
  /// правят их в окне выбора вида, и следующий кадр обязан это учесть.
  final PanelsSettings Function() settings;

  /// Записать настройки: ширину первого столбца правят мышью.
  final VoidCallback save;

  @override
  State<ColumnsView> createState() => ColumnsViewState();
}

class ColumnsViewState extends State<ColumnsView> {
  /// Лента едет туда, где стояла: смещение задаётся при создании контроллера,
  /// а не подмоткой следующим кадром — иначе возврат из полноэкранного вида
  /// видно глазами (`file_table.dart`).
  late final ScrollController _ribbon = ScrollController(initialScrollOffset: widget.panel.scrollOffset);

  /// Прокрутка столбцов — **по пути владельца**, а не по номеру: цепочка
  /// укорачивается и растёт, а номера при этом съезжают.
  final Map<String, ScrollController> _verticals = {};

  /// Подстроенная мышью ширина столбца — тем же ключом, что и прокрутка.
  ///
  /// Перезапуск она не переживает, и это решение, а не недоделка: из пути её не
  /// вывести (в отличие от вертикали), а держать в настройках по числу на
  /// каждый посещённый каталог значило бы копить мусор ради мелочи
  /// (`docs/spec/panel-view-columns.md`, §8).
  final Map<String, double> _widths = {};

  final ChainMemo _memo = ChainMemo();

  /// Окно, в пределах которого два щелчка по одной строке считаются двойным.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  /// По чему опознаётся второй щелчок — **по пути**, а не по номеру строки.
  ///
  /// В этом виде номера разъезжаются сами: придержка раскрывает каталог, уход
  /// курсора сворачивает раскрытое ею же, и строки ниже съезжают на всю
  /// глубину поддерева. Номер, запомненный до этого, назавтра означает **другую
  /// строку** — и одиночный щелчок по ней читается вторым, а вторым здесь
  /// значит «войти». Снаружи это выглядит так: человек ходит курсором, а
  /// панель самопроизвольно проваливается внутрь каталога.
  ///
  /// В таблице номером можно: там список сам собой не перестраивается.
  String _lastTapPath = '';
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Высота строки вместе с просветом; 0 — разметки ещё не было.
  double _step = 0;

  /// Высота списка в столбце — без шапки: по ней считается страница и
  /// подмотка к строке.
  double _height = 0;

  /// Высота шапки столбца: она входит в столбец, но не в список.
  double _headerHeight = 0;

  /// Раскладка ленты на последнем кадре: по ней жест пометки узнаёт, в каком
  /// столбце указатель и какая строка под ним.
  ColumnChain _shownChain = ColumnChain.empty;
  List<double> _shownWidths = const [];
  List<double> _shownEdges = const [];

  /// Столбец, в котором курсор стоял в прошлый показ; -1 — не стоял нигде.
  ///
  /// По нему видно, был ли ход **вбок**: только он и двигает ленту.
  int _revealedColumn = -1;

  /// Столбец, в котором начался жест пометки; -1 — жеста нет.
  ///
  /// Отрезок пометки зажимается в нём: столбцы — это разные каталоги, и тянуть
  /// пометку из одного в другой значит помечать невидимое.
  int _markColumn = -1;

  /// Пометка правой кнопкой — жест общий с таблицей, сеткой и деревом
  /// (`docs/spec/mouse-marking.md`).
  late final MarkDrag _marking = MarkDrag(
    panel: widget.panel,
    indexAt: _indexAt,
    indexNear: _indexNear,
    bounds: () => (_headerHeight, _headerHeight + _height),
    scroll: _markScroll,
    activate: () => AppScope.read(context).activate(widget.panel),
    rowsBetween: _rowsBetween,
  );

  /// Отсчёт придержки и каталог, на котором он заведён.
  Timer? _hold;
  String? _holding;

  /// Ветвь, раскрытая **самим видом**; null — вид ничего не раскрывал.
  ///
  /// Помнится одна: столько их и бывает — придержка раскрывает то, на чём
  /// стоит курсор, а уходя, вид за собой убирает. Раскрытое руками сюда не
  /// попадает и не трогается: это выбор человека.
  String? _opened;

  /// Что показывали в прошлый раз: по смене видно, что пора подматывать.
  int _shownCursor = -1;
  int _shownCount = -1;

  @override
  void initState() {
    super.initState();
    // Вид говорит, что ему нужно; собирать строки — дело ядра
    // (`docs/spec/panel-node-list.md`, §3).
    unawaited(widget.panel.showRows(RowsKind.tree));
  }

  @override
  void dispose() {
    _marking.dispose();
    _hold?.cancel();
    for (final controller in _verticals.values) {
      controller.dispose();
    }
    _ribbon.dispose();
    super.dispose();
  }

  /// Строки, которые вид **просил**: ветви.
  ///
  /// Пока ядро не ответило на просьбу (`showRows`), в панели лежит набор
  /// прежнего вида — списочный, — и нарезать его столбцами нельзя: уровни в
  /// нём у всех нулевые, и вышел бы один столбец из всего каталога.
  List<FileEntry> get _rows => widget.panel.rows.isTree ? widget.panel.entries : const [];

  ScrollController _verticalOf(String path) => _verticals.putIfAbsent(path, () => ScrollController());

  /// Забыть прокрутку столбцов, которых в цепочке больше нет.
  ///
  /// Иначе прогулка по дереву оставляла бы за собой по контроллеру на каждый
  /// посещённый каталог — а живут они до закрытия панели.
  void _forgetGone(ColumnChain chain) {
    final live = {for (final column in chain.columns) _rows[column.owner].path};
    final gone = _verticals.keys.where((path) => !live.contains(path)).toList();
    for (final path in gone) {
      _verticals.remove(path)?.dispose();
    }
  }

  /// Держать на виду то, что человек выбрал: в каждом столбце — своё звено
  /// цепочки, в ленте — текущий столбец.
  ///
  /// Обещание скромное и честное: звено **видно**. Ровно на той же строке, что
  /// при закрытии, оно стоять не обязано — вертикаль столбцов нигде не
  /// хранится, она выводится из пути (`panel-view-columns.md`, §8а).
  void _reveal(ColumnChain chain) {
    if (_step <= 0 || _height <= 0) {
      return;
    }
    for (var at = 0; at < chain.columns.length; at++) {
      final column = chain.columns[at];
      final row = at == chain.current ? widget.panel.cursorIndex : column.selected;
      final place = column.rows.indexOf(row);
      if (place < 0) {
        continue;
      }
      final controller = _verticalOf(_rows[column.owner].path);
      if (!controller.hasClients) {
        continue;
      }
      final limit = (column.rows.length * _step - _height).clamp(0.0, double.infinity);
      final offset = controller.offset;
      final top = place * _step;
      final bottom = top + _step;
      final target = switch (0) {
        _ when top < offset => top,
        _ when bottom > offset + _height => (bottom - _height).clamp(0.0, limit),
        _ => offset,
      };
      if (target != offset) {
        controller.jumpTo(target);
      }
    }

    // Лента едет **только когда курсор сменил столбец** — вправо к детям, влево
    // к родителю. Ходьба внутри столбца её не трогает: там человек читает
    // список, и уезжающая под руками лента отнимает у глаза единственную
    // опору. Живой разбор 17 сентября 2026: придержка раскрывала соседний
    // каталог, лента доезжала до нового столбца — и всё содержимое прыгало
    // вбок, хотя курсор шёл вниз.
    final sideways = chain.current != _revealedColumn;
    _revealedColumn = chain.current;
    if (sideways) {
      _revealColumn(chain);
    } else {
      _keepColumnVisible(chain);
    }
  }

  /// Столбец с курсором скрылся целиком — вернуть его на экран.
  ///
  /// Единственное, ради чего лента трогается при ходьбе внутри столбца: увести
  /// его из виду могли не мы (тяга ширины, смена размера окна), а курсор,
  /// которого не видно, — это уже не «не дёргать», а «потерять».
  void _keepColumnVisible(ColumnChain chain) {
    final at = chain.current;
    if (at < 0 || !_ribbon.hasClients) {
      return;
    }
    final width = _columnWidth();
    final step = width + _dividerWidth;
    final left = at * step;
    final right = left + width;
    final view = _ribbon.position.viewportDimension;
    final offset = _ribbon.offset;
    if (right > offset && left < offset + view) {
      return;
    }
    _revealColumn(chain);
  }

  /// Виден текущий столбец **и место под следующий** — всегда, даже когда
  /// следующего ещё нет.
  ///
  /// Место отводится сразу, потому что в этом и смысл вида: содержимое
  /// каталога под курсором видно **заранее**, а не после того, как курсор туда
  /// перейдёт. Живой разбор 17 сентября 2026: доходя до последнего столбца,
  /// лента стояла, и содержимое показывалось только после шага вправо.
  ///
  /// И потому что иначе лента дёргается: идёшь мимо каталогов, столбец справа
  /// то появляется (каталог), то исчезает (файл, пустой каталог), — и всякий
  /// раз меняется ширина ленты, а вместе с ней и предел прокрутки. Место,
  /// отведённое заранее, держит и то и другое неподвижным: новый столбец
  /// встаёт в готовую нишу.
  void _revealColumn(ColumnChain chain) {
    final at = chain.current;
    if (at < 0 || !_ribbon.hasClients) {
      return;
    }
    final width = _columnWidth();
    final step = width + _dividerWidth;
    final left = at * step;
    // Правый край следующего столбца — **если он есть**. Место под него
    // отведено всегда (ниже, в раскладке), но ехать ради пустой ниши незачем:
    // в узкой панели это спрятало бы родительский столбец ради пустоты.
    final next = at + 1 < chain.columns.length;
    final right = next ? left + step + width : left + width;
    final view = _ribbon.position.viewportDimension;
    final limit = _ribbon.position.maxScrollExtent;
    final offset = _ribbon.offset;

    var target = offset;
    if (right > offset + view) {
      target = right - view;
    }
    // Курсор важнее показанного впрок: в узкой панели, где двум столбцам не
    // поместиться, виден тот, в котором работают.
    if (left < target) {
      target = left;
    }
    target = target.clamp(0.0, limit);
    if (target != offset) {
      _ribbon.jumpTo(target);
    }
  }

  /// Ширина первого столбца — общая настройка приложения.
  double _columnWidth() => widget.settings().columnWidth.toDouble();

  /// Ширины столбцов цепочки, слева направо.
  ///
  /// Наследование — **разовое**: столбец, открывшийся впервые, берёт ширину
  /// того, из кого вышли, и с этого мига живёт своей. Так подстройка не
  /// сбрасывается на каждом шаге вглубь — и не расползается обратно: потянув
  /// один столбец, человек правит один столбец, а не всю цепочку.
  ///
  /// Первый ни за кем не повторяет: его ширина — общая настройка приложения.
  List<double> _widthsOf(ColumnChain chain, List<FileEntry> rows) {
    final widths = <double>[];
    var inherited = _columnWidth();
    for (var at = 0; at < chain.columns.length; at++) {
      if (at > 0) {
        // Запоминается при первом показе, а не при первой тяге: иначе
        // «ширина родителя» означала бы его **нынешнюю** ширину, и правка
        // одного столбца ехала бы по всем, кто за ним следом.
        inherited = _widths[rows[chain.columns[at].owner].path] ??= inherited;
      }
      widths.add(inherited);
    }
    return widths;
  }

  /// Ширину тянут у столбца **слева** от границы: она и меняется, и только она.
  void _resize(ColumnChain chain, List<FileEntry> rows, int at, double width) {
    final value = width.clamp(PanelsSettings.minColumnWidth.toDouble(), PanelsSettings.maxColumnWidth.toDouble());
    setState(() {
      if (at == 0) {
        // Первый столбец — общая настройка приложения: от него наследуют
        // остальные, и переживать перезапуск должен именно он.
        widget.settings().columnWidth = value.round();
        widget.save();
      } else {
        _widths[rows[chain.columns[at].owner].path] = value;
      }
    });
  }

  /// Двойной щелчок по границе — вернуть столбцу ширину родителя.
  void _resetWidth(ColumnChain chain, List<FileEntry> rows, int at) {
    setState(() {
      if (at == 0) {
        widget.settings().columnWidth = PanelsSettings.defaultColumnWidth;
        widget.save();
      } else {
        _widths.remove(rows[chain.columns[at].owner].path);
      }
    });
  }

  /// Линейка между столбцами — она же весь зазор между ними.
  double get _dividerWidth => FcTheme.of(context).metrics.strokeWidth;

  /// Столбец под указателем; -1 — мимо столбцов.
  int _columnAt(Offset local) {
    if (_shownWidths.isEmpty) {
      return -1;
    }
    final x = local.dx + (_ribbon.hasClients ? _ribbon.offset : 0);
    for (var at = 0; at < _shownWidths.length; at++) {
      if (x >= _shownEdges[at] && x < _shownEdges[at] + _shownWidths[at]) {
        return at;
      }
    }
    return -1;
  }

  /// Строка под указателем; null — мимо строк (шапка, пустое место, зазор).
  int? _indexAt(Offset local) {
    final at = _columnAt(local);
    if (at < 0 || _step <= 0 || local.dy < _headerHeight) {
      return null;
    }
    final rows = _shownChain.columns[at].rows;
    final offset = _scrollOf(at);
    final place = ((local.dy - _headerHeight + offset) / _step).floor();
    return place >= 0 && place < rows.length ? rows[place] : null;
  }

  /// Строка, к которой тянут: за краями — крайняя видимая **своего** столбца.
  ///
  /// Своего, а не того, над которым рука: столбцы — разные каталоги, и уехать
  /// пометке в соседний нельзя.
  int _indexNear(Offset local) {
    final at = _markColumn >= 0 ? _markColumn : _columnAt(local);
    if (at < 0 || at >= _shownChain.columns.length || _step <= 0) {
      return widget.panel.cursorIndex;
    }
    final rows = _shownChain.columns[at].rows;
    if (rows.isEmpty) {
      return widget.panel.cursorIndex;
    }
    final bottom = _headerHeight + _height;
    final dy = local.dy.clamp(_headerHeight, math.max(_headerHeight, bottom - 1));
    final place = ((dy - _headerHeight + _scrollOf(at)) / _step).floor().clamp(0, rows.length - 1);
    return rows[place];
  }

  /// Строки **своего столбца** между двумя номерами: чужое раскрытое
  /// поддерево, лежащее между соседями по каталогу, пометке не достаётся.
  List<int> _rowsBetween(int low, int high) {
    if (_markColumn < 0 || _markColumn >= _shownChain.columns.length) {
      return [for (var i = low; i <= high; i++) i];
    }
    return [
      for (final row in _shownChain.columns[_markColumn].rows)
        if (row >= low && row <= high) row,
    ];
  }

  double _scrollOf(int at) {
    final rows = _shownChain.columns;
    if (at < 0 || at >= rows.length) {
      return 0;
    }
    final controller = _verticals[_rows[rows[at].owner].path];
    return controller != null && controller.hasClients ? controller.offset : 0;
  }

  /// Чем едет список у края: вертикалью того столбца, в котором начался жест.
  ScrollController _markScroll() {
    final at = _markColumn;
    final columns = _shownChain.columns;
    if (at >= 0 && at < columns.length) {
      return _verticalOf(_rows[columns[at].owner].path);
    }
    return _ribbon;
  }

  /// Курсор постоял на закрытом каталоге — раскрыть его.
  ///
  /// Три ограничения, и все три из набитых шишек: только в активной панели;
  /// только **из таймера** (к ядру из-под уведомления ходить нельзя — это
  /// «Cannot fire new event»); и каталог пересчитывается в момент
  /// срабатывания, а не запоминается при заводе отсчёта — за 150 мс курсор мог
  /// уехать, а список перечитаться.
  void _scheduleHold(FileEntry? under) {
    final wanted = under != null && under.isDirectory && !under.isOpen && widget.panel.active ? under.path : null;
    if (wanted == _holding) {
      return;
    }
    _hold?.cancel();
    _holding = wanted;
    if (wanted == null) {
      return;
    }
    _hold = Timer(ColumnsView.holdBeforeOpen, () {
      if (!mounted) {
        return;
      }
      final row = _rowUnderCursor();
      if (row == null || row.path != wanted || row.isOpen || !widget.panel.active) {
        return;
      }
      _opened = wanted;
      widget.panel.setExpanded(wanted, expanded: true);
    });
  }

  /// Убрать за собой: раскрытое видом сворачивается, когда курсор ушёл.
  ///
  /// Иначе неделя прогулок по столбцам превратит `Cmd-3` в кусты: память
  /// раскрытого общая с деревом и уезжает в настройки.
  void _tidyUp(ColumnChain chain) {
    final opened = _opened;
    if (opened == null) {
      return;
    }
    final rows = _rows;
    // Курсор всё ещё там, если раскрытая ветвь стоит на его цепочке: сам он
    // может уйти и вглубь — это не «ушёл».
    final onChain =
        chain.columns.any((column) => rows[column.owner].path == opened) || _rowUnderCursor()?.path == opened;
    if (onChain) {
      return;
    }
    _opened = null;
    widget.panel.setExpanded(opened, expanded: false);
  }

  FileEntry? _rowUnderCursor() {
    final rows = _rows;
    final at = widget.panel.cursorIndex;
    return at >= 0 && at < rows.length ? rows[at] : null;
  }

  /// Щелчок ставит курсор, двойной — входит.
  ///
  /// Распознаётся вручную, как везде: штатный `onDoubleTap` придерживает
  /// первый щелчок до конца окна, и курсор начинает опаздывать.
  void _onTap(int index) {
    final rows = _rows;
    if (index < 0 || index >= rows.length) {
      return;
    }
    final path = rows[index].path;
    final now = DateTime.now();
    final again = path == _lastTapPath && now.difference(_lastTapTime) < _doubleTapWindow;
    _lastTapPath = path;
    _lastTapTime = now;

    AppScope.read(context).activate(widget.panel);
    widget.panel.setCursorToPath(path);
    if (again) {
      _lastTapPath = '';
      enterAt(index);
    }
  }

  /// Войти: каталог — внутрь, файл — открыть.
  ///
  /// Внутрь — то же самое, что делает `Right`: раскрыть и шагнуть на первую
  /// строку. Не `enterCurrent`: тот сменил бы каталог панели, а столбцы на то и
  /// столбцы, чтобы остаться на месте и увидеть содержимое справа.
  void enterAt(int index) {
    final rows = _rows;
    if (index < 0 || index >= rows.length) {
      return;
    }
    final row = rows[index];
    if (!row.isDirectory) {
      unawaited(widget.panel.enterCurrent());
      return;
    }
    if (!row.isOpen) {
      // Раскрыл человек — убирать за ним нечего.
      _opened = null;
      widget.panel.setExpanded(row.path, expanded: true);
      return;
    }
    if (index + 1 < rows.length && rows[index + 1].level > row.level) {
      widget.panel.setCursorToPath(rows[index + 1].path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: panel,
      builder: (context, _) {
        // Вбок и вниз здесь ходят свои команды: шаг переменный, и постоянным
        // числом строк его не описать (`panel-view-columns.md`, §6).
        panel.cursorSteps = const PanelSteps.list();

        final app = AppScope.read(context);
        // Шаг строки — тот же, что в списке и в дереве: панели стоят рядом, и
        // строки обязаны сходиться.
        _step = FileIconSize.listRow(theme.metrics, app.fileIcons);

        final rows = _rows;
        final chain = _memo.of(rows, panel.cursorIndex);
        _forgetGone(chain);
        _scheduleHold(_rowUnderCursor());

        if (panel.cursorIndex != _shownCursor || rows.length != _shownCount) {
          _shownCursor = panel.cursorIndex;
          _shownCount = rows.length;
          // И подмотка, и уборка — **после кадра**: та зовёт ядро, а к ядру
          // из-под разметки ходить нельзя (`panel-state-races`).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final chain = _memo.of(_rows, widget.panel.cursorIndex);
              _reveal(chain);
              _tidyUp(chain);
            }
          });
        }

        final width = _columnWidth();
        final divider = theme.metrics.strokeWidth;

        // Слой пометки стоит **всегда**, а не появляется вместе с жестом:
        // строение вида посреди работы мышью меняться не вправе
        // (`docs/spec/drag-and-drop.md`).
        return Listener(
          onPointerDown: (event) {
            if (MarkDrag.isMarking(event.buttons)) {
              _markColumn = _columnAt(event.localPosition);
            }
            _marking.down(event);
          },
          onPointerMove: _marking.move,
          onPointerUp: (event) {
            _markColumn = -1;
            _marking.up(event);
          },
          onPointerCancel: (event) {
            _markColumn = -1;
            _marking.up(event);
          },
          child: NotificationListener<ScrollEndNotification>(
            // Запоминается **горизонталь ленты**: её из пути не вывести, в
            // отличие от вертикали столбцов (§8а). Сообщение идёт по покое, а не
            // на каждую точку: иначе через границу поехала бы лента сообщений.
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.horizontal) {
                panel.setScrollOffset(notification.metrics.pixels);
              }
              return false;
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Шапка входит в столбец, но не в список: страница считается по
                // тому, что и правда листается.
                _height = (constraints.maxHeight - theme.metrics.headerRowHeight).clamp(0.0, constraints.maxHeight);
                // Страница — то, что видно в столбце: `PgUp`/`PgDn` листают
                // ровно столько, сколько человек перед собой видит.
                panel.pageSize = (_height / _step).floor().clamp(1, 1000);

                _headerHeight = theme.metrics.headerRowHeight;
                final widths = _widthsOf(chain, rows);
                // Левые края столбцов — по ним же стоят и захваты границ.
                final edges = <double>[];
                var x = 0.0;
                for (final one in widths) {
                  edges.add(x);
                  x += one + divider;
                }
                // Место под следующий столбец — отведено всегда, даже когда
                // показывать в нём нечего: так содержимое видно заранее, а лента
                // не дёргается от появления и пропажи столбца.
                final lane = x + (widths.isEmpty ? width : widths.last);

                // Раскладка запоминается для жеста пометки: он живёт в
                // координатах ленты и должен знать, где чей столбец.
                _shownChain = chain;
                _shownWidths = widths;
                _shownEdges = edges;

                return SingleChildScrollView(
                  controller: _ribbon,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    height: constraints.maxHeight,
                    width: lane,
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var at = 0; at < chain.columns.length; at++) ...[
                              if (at > 0)
                                SizedBox(width: divider, child: ColoredBox(color: theme.colors.columnDivider)),
                              SizedBox(
                                width: widths[at],
                                child: _Column(
                                  panel: panel,
                                  rows: rows,
                                  column: chain.columns[at],
                                  // Строка, из которой вырос столбец справа; -1 —
                                  // столбец последний. Спрашивается у цепочки, а не
                                  // выводится из `selected`: в последнем столбце
                                  // выбранное — это курсор, и справа от него может не
                                  // быть ничего (файл, закрытая ветвь).
                                  nextOwner: at + 1 < chain.columns.length ? chain.columns[at + 1].owner : -1,
                                  current: at == chain.current,
                                  step: _step,
                                  controller: _verticalOf(rows[chain.columns[at].owner].path),
                                  onTap: _onTap,
                                ),
                              ),
                            ],
                            SizedBox(width: divider, child: ColoredBox(color: theme.colors.columnDivider)),
                            const Expanded(child: SizedBox.expand()),
                          ],
                        ),
                        // Захваты границ — **поверх** столбцов, а не в зазоре
                        // между ними: проверка попадания идёт по размеру
                        // родителя, и всё, что нарисовано шире зазора, до жеста
                        // не доходит (урок `FcSplitView`).
                        for (var at = 0; at < widths.length; at++)
                          Positioned(
                            left: edges[at] + widths[at] + divider / 2 - _ColumnGrip.width / 2,
                            top: 0,
                            bottom: 0,
                            width: _ColumnGrip.width,
                            child: _ColumnGrip(
                              // Ширина считается **от положения указателя**, а не
                              // набегает из его смещений: смещения приходят чаще,
                              // чем рисуются кадры, и граница отставала бы тем
                              // сильнее, чем быстрее движение (урок `FcSplitView`).
                              onDrag: (position) => _resize(chain, rows, at, position - edges[at]),
                              onReset: () => _resetWidth(chain, rows, at),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Один столбец: содержимое одного каталога, без отступов и заголовка.
class _Column extends StatelessWidget {
  const _Column({
    required this.panel,
    required this.rows,
    required this.column,
    required this.nextOwner,
    required this.current,
    required this.step,
    required this.controller,
    required this.onTap,
  });

  final Session panel;
  final List<FileEntry> rows;
  final ChainColumn column;

  /// Строка, чьё содержимое показывает столбец справа; -1 — столбец последний.
  final int nextOwner;

  /// Курсор стоит в этом столбце.
  final bool current;

  final double step;
  final ScrollController controller;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    // Шапка называет **каталог**, чьё содержимое в столбце, — то самое
    // последнее звено пути, из которого этот столбец вырос. Не колонка: имя,
    // размер и дата здесь ни при чём, столбец один и всегда с именами.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_ColumnHeader(name: rows[column.owner].name), Expanded(child: _list(context))],
    );
  }

  Widget _list(BuildContext context) {
    // Пустой столбец — не то же, что отсутствие столбца: «здесь пусто» надо
    // показать, иначе оно неотличимо от «сюда не входили».
    return ListView.builder(
      controller: controller,
      itemExtent: step,
      itemCount: column.rows.length,
      itemBuilder: (context, place) {
        final index = column.rows[place];
        final row = rows[index];
        return _ColumnRow(
          row: row,
          underCursor: current && index == panel.cursorIndex,
          // Вошли — значит этот каталог и показан столбцом справа.
          entered: index == nextOwner,
          onTrail: !current && index == column.selected,
          marked: panel.isMarked(row),
          panelActive: takesKeysHere(context, panel),
          onTap: () => onTap(index),
        );
      },
    );
  }
}

/// Захват границы столбца: тянут — меняется столбец слева от неё.
///
/// Свой, а не `FcSplitView`: тот про две стороны и одну долю, а здесь сторон
/// сколько угодно и меряются они в точках. Но два правила, добытых кровью,
/// перенесены дословно — ширина считается от положения указателя, и сам захват
/// лежит поверх столбцов (`docs/spec/panel-view-columns.md`, §8).
class _ColumnGrip extends StatelessWidget {
  const _ColumnGrip({required this.onDrag, required this.onReset});

  /// Насколько широк захват. Шире линейки: попасть в линию толщиной в точку
  /// мышью нельзя.
  static const double width = 10;

  /// Положение указателя внутри ленты — в её собственных координатах.
  final void Function(double position) onDrag;

  /// Вернуть столбцу ширину родителя.
  final VoidCallback onReset;

  /// Где указатель внутри ленты.
  ///
  /// Считается от **ленты**, а не от самого захвата: тот во время
  /// перетаскивания едет, и мерить от него значило бы мерить от подвижной
  /// точки.
  static double? _positionIn(BuildContext context, Offset global) {
    final box = context.findAncestorRenderObjectOfType<RenderBox>();
    return box != null && box.hasSize ? box.globalToLocal(global).dx : null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final position = _positionIn(context, details.globalPosition);
          if (position != null) {
            onDrag(position);
          }
        },
        onDoubleTap: onReset,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Шапка столбца: имя каталога, чьё содержимое в нём показано.
///
/// Той же высоты и тем же набором, что заголовки колонок таблицы и дерева:
/// панели стоят рядом, и первая строка списка обязана начинаться на одной
/// вертикали с соседней. Жестов у неё нет — сортировать столбец нечем: колонка
/// здесь одна, и правило порядка у панели общее.
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    return SizedBox(
      height: theme.metrics.headerRowHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: theme.metrics.cellPadding),
        child: Center(
          // Имя каталога — данные, а не ключ перевода: `tr` здесь было бы
          // ошибкой, а длинное имя договаривается подсказкой само.
          child: FcTrimmedText(text: name, style: theme.headerStyle, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Строка столбца: значок, имя и знак «дальше вправо» у каталога.
class _ColumnRow extends StatelessWidget {
  const _ColumnRow({
    required this.row,
    required this.underCursor,
    required this.entered,
    required this.onTrail,
    required this.marked,
    required this.panelActive,
    required this.onTap,
  });

  final FileEntry row;

  final bool underCursor;

  /// Строка, из которой вышли: столбец левее текущего.
  ///
  /// Её имя пишется **ярким** и на обычном фоне — тем же приёмом, каким
  /// навигатор комбинированного вида показывает ветвь, чей список виден рядом
  /// (`docs/spec/panel-view-combined.md`, §5а). Курсор один, и полосы у
  /// пройденного звена быть не должно: двух курсоров на экране не бывает, —
  /// но видеть, откуда взялся столбец справа, надо, иначе путь читается
  /// только с конца.
  final bool onTrail;

  /// В этот каталог вошли: справа стоит столбец с его содержимым.
  ///
  /// Только у него и есть знак «дальше вправо». У каждого каталога он обещал бы
  /// то, чего на экране нет: столбец справа один, и вырос он ровно из этой
  /// строки.
  final bool entered;

  final bool marked;
  final bool panelActive;
  final VoidCallback onTap;

  bool get _selected => underCursor && panelActive;

  /// Имя пишется ярким: под курсором — на полосе, на цепочке — на обычном фоне.
  bool get _bright => _selected || onTrail;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;

    final style = _bright ? theme.rowStyle.copyWith(color: colors.cursorText) : theme.rowStyle;
    // Знак «дальше вправо» — тот же шеврон, что закрытая ветвь в дереве: он и
    // там, и здесь значит «дальше в эту сторону».
    final glyph = TextStyle(
      fontFamily: theme.icons.fontFamily,
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
          // курсором. Пройденное звено фона не получает вовсе — только имя.
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
                padding: EdgeInsets.only(left: metrics.iconLeftPadding),
                child: Transform.translate(
                  offset: Offset(0, metrics.rowContentVerticalNudge),
                  child: Row(
                    children: [
                      FileTypeIcon(entry: row, selected: _selected),
                      SizedBox(width: metrics.iconGap),
                      Expanded(
                        child: Transform.translate(
                          offset: Offset(0, metrics.rowTextVerticalNudge),
                          child: FcTrimmedText(text: row.name, style: style),
                        ),
                      ),
                      if (entered)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding),
                          child: Text(String.fromCharCode(theme.icons.branchClosed.codePoint), style: glyph),
                        ),
                    ],
                  ),
                ),
              ),
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
