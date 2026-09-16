import 'dart:async';
import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'cursor_pin.dart';
import 'icon_tile.dart';
import 'mark_drag.dart';
import 'panel_drag.dart';
import 'panels_settings.dart';
import 'widest_name.dart';

/// Вид «Значки»: содержимое каталога сеткой плиток.
///
/// Спецификация — `docs/spec/panel-view-icons.md`.
///
/// Раскладка одного и того же списка, а не второй список: курсор, пометка и
/// порядок — панельные (`docs/spec/panel-views.md`, §4). От краткого вида
/// отличается поворотом: там столбцы едут вбок, здесь ряды идут вниз.
class IconsView extends StatefulWidget {
  const IconsView({super.key, required this.panel, required this.settings});

  /// Имя вида — оно же ключ настройки панели.
  static const String viewId = 'icons';

  final Session panel;

  /// Способ узнать настройки, а не их значение: их правят в окне выбора вида, и
  /// следующая же отрисовка должна идти по новым.
  final PanelsSettings Function() settings;

  @override
  State<IconsView> createState() => _IconsViewState();
}

class _IconsViewState extends State<IconsView> {
  /// Окно, в пределах которого два щелчка по одной плитке считаются двойным.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  /// Сколько места имя вправе занять, когда его не задали настройкой: вдвое от
  /// стороны значка.
  ///
  /// **От значка, а не от панели.** Пока мера была долей панели — четвертью, —
  /// окно пошире делало плитки шире, а не многочисленнее: столбцов всегда
  /// оставалось четыре, а просветы между значками росли, как при растягивании
  /// по ширине, от которого мы отказались (§3 спеки).
  ///
  /// Вдвое: при 64 точках это 128 — около двух десятков знаков в строке, то
  /// есть сорок на две строки. Имена длиннее встречаются, но договаривает их
  /// подсказка, а не сетка.
  static const double _nameToIcon = 2;

  /// Упоры, между которыми держится этот потолок.
  ///
  /// Снизу — чтобы при мелком значке имя не сжималось в огрызок: значок в 16
  /// точек не повод показывать четыре знака имени. Сверху — чтобы при крупном
  /// плитка не расползалась: 256 точек под имя это уже не сетка, а список с
  /// картинками.
  static const double _leastName = 80;
  static const double _mostName = 160;

  /// Список сразу встаёт туда, где стоял: начальное смещение задаётся при
  /// создании контроллера, а не подмоткой следующим кадром.
  late final ScrollController _scroll = ScrollController(initialScrollOffset: widget.panel.scrollOffset);

  /// Прокрутку запомнили — можно о ней и рассказывать.
  bool _shown = false;

  /// Раскладка последней отрисовки: по ней прокрутка держит курсор на виду ещё
  /// до того, как случится следующая.
  double _tileWidth = 0;
  double _tileHeight = 0;
  double _rowHeight = 0;
  double _viewHeight = 0;
  int _columns = 1;

  /// Плитка под курсором с прошлого показа — чтобы перестановка её не сдвинула.
  final CursorPin _pin = CursorPin();

  /// Пометка правой кнопкой — жест общий со списком (`spec/mouse-marking.md`).
  ///
  /// Отрезок он считает по порядку списка, а не по прямоугольнику: плитки
  /// разложены рядами, и «от этой до той» читается так же, как в списке — по
  /// дороге, которой идёт курсор.
  late final MarkDrag _marking = MarkDrag(
    panel: widget.panel,
    indexAt: _indexAt,
    indexNear: _tileNear,
    bounds: () => (0, _viewHeight),
    scroll: () => _scroll,
    activate: () => AppScope.read(context).activate(widget.panel),
  );

  /// Самое длинное имя списка — общей меркой с кратким видом.
  final WidestName _widest = WidestName();

  int _lastCursorIndex = -1;
  int _lastTapIndex = -1;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _askRows();
  }

  @override
  void didUpdateWidget(IconsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel != widget.panel) {
      _askRows();
    }
  }

  /// Строки, которые вид **просил**: содержимое каталога.
  ///
  /// Пока ядро не ответило, в панели лежит набор прежнего вида — например,
  /// древесный, — и раскладывать его плитками нельзя
  /// (`docs/spec/panel-node-list.md`, §3).
  List<FileEntry> get _shownRows => widget.panel.rows == RowsKind.listing ? widget.panel.entries : const [];

  /// Вид говорит, что ему нужно: строки каталога.
  void _askRows() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.panel.showRows(RowsKind.listing));
      }
    });
  }

  @override
  void dispose() {
    _marking.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Докрутить так, чтобы ряд с курсором стоял целиком.
  ///
  /// По рядам, а не по точкам: ряд — единица раскладки, и половина ряда у края
  /// читалась бы обрезком.
  void _revealCursor() {
    if (!_scroll.hasClients || _rowHeight <= 0 || _viewHeight <= 0 || _columns <= 0) {
      return;
    }
    final rows = widget.panel.entries;
    final at = widget.panel.cursorIndex;
    final row = at ~/ _columns;

    // Список переставили — ряд с курсором остаётся там же, где был: то же
    // правило, что и при смене раскладки (`docs/spec/panel-views.md`, §9).
    // Запоминается **всегда**, флажок или нет: иначе после выключения и
    // включения закрепление сработало бы от устаревшего места.
    final from = widget.settings().cursorHoldsPlace ? _pin.movedFrom(rows, at) : null;
    _pin.remember(rows, at);
    final offset =
        from == null
            ? _scroll.offset
            : (_scroll.offset + (row - from ~/ _columns) * _rowHeight).clamp(0.0, _scroll.position.maxScrollExtent);

    // Место ряда считается вместе с полем сверху: оно лежит внутри прокрутки.
    final top = _top + row * _rowHeight;
    final bottom = top + _rowHeight;
    // Плашка пути лежит поверх рамы и закрывает её верх наполовину своей
    // высоты: докручивая вверх, ряд ставим ниже этого края — иначе он приедет
    // под плашку, и курсора не будет видно.
    final target = switch (0) {
      _ when top - offset < _headroom => top - _headroom,
      _ when bottom > offset + _viewHeight => bottom - _viewHeight,
      _ => offset,
    };
    if (target != _scroll.offset) {
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  /// Где на экране верх ряда с курсором; null — прокрутки ещё нет.
  ///
  /// Считается **до** новой раскладки, по прежним числам: после неё плитка
  /// попала в другой ряд, и вернуть его на место можно только зная, где он был.
  double? _cursorRowOnScreen() {
    if (!_scroll.hasClients || _rowHeight <= 0 || _columns <= 0) {
      return null;
    }
    return _top + (widget.panel.cursorIndex ~/ _columns) * _rowHeight - _scroll.offset;
  }

  /// Вернуть ряд с курсором туда же, где он стоял на экране.
  ///
  /// Не влез — обычная докрутка: обещание «ничего не поехало» кончается там,
  /// где ряд перестал помещаться.
  void _pinCursorRow(double? was) {
    if (!_scroll.hasClients || was == null || _rowHeight <= 0) {
      _revealCursor();
      return;
    }
    final target = _top + (widget.panel.cursorIndex ~/ _columns) * _rowHeight - was;
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    _revealCursor();
  }

  /// Номер строки под точкой — в местных координатах области; null — мимо.
  ///
  /// Просвет считается частью левой плитки: щелчок между плитками попадает в
  /// соседку, а не в никуда. То же правило, что у краткого вида.
  int? _indexAt(Offset local) {
    if (_tileWidth <= 0 || _rowHeight <= 0 || _columns <= 0) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    // Поле вокруг содержимого сдвинуло сетку: указатель приходит в координатах
    // области, а плитки стоят внутри поля.
    final column = ((local.dx - _gap) / _step).floor();
    final row = ((local.dy - _top + offset) / _rowHeight).floor();
    if (column < 0 || column >= _columns || row < 0) {
      return null;
    }
    final index = row * _columns + column;
    return index >= 0 && index < widget.panel.entries.length ? index : null;
  }

  /// Шаг сетки вбок: плитка и просвет за ней.
  double get _step => _tileWidth + _gap;

  double _gap = 0;

  /// Поле сверху: просвет сетки и место под плашкой пути.
  double _top = 0;

  /// Сколько рамы закрывает плашка пути сверху.
  double _headroom = 0;

  /// Плитка, к которой тянут: за краями сетки — крайняя видимая, а не
  /// последняя в каталоге.
  ///
  /// Иначе указатель, ушедший за нижний край, помечал бы каталог до конца одним
  /// махом; а так отрезок растёт по мере того, как сетка едет.
  int _tileNear(Offset local) {
    final entries = widget.panel.entries;
    if (_step <= 0 || _rowHeight <= 0 || _columns <= 0 || entries.isEmpty) {
      return 0;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final dy = local.dy.clamp(0.0, math.max(0.0, _viewHeight - 1));
    final row = math.max(0, ((dy - _top + offset) / _rowHeight).floor());
    final column = ((local.dx - _gap) / _step).floor().clamp(0, _columns - 1);
    return (row * _columns + column).clamp(0, entries.length - 1);
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

  /// Обводится **плитка**: в сетке строка занимает ячейку, а не всю ширину.
  Rect? _highlightOf(DropSpot spot) {
    final entry = spot.entry;
    final index = entry == null ? -1 : widget.panel.entries.indexOf(entry);
    if (index < 0 || _tileWidth <= 0 || _columns <= 0) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    return Rect.fromLTWH(
      _gap + (index % _columns) * _step,
      _top + (index ~/ _columns) * _rowHeight - offset,
      _tileWidth,
      _tileHeight,
    );
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
              final entries = _shownRows;
              final metrics = theme.metrics;

              final iconSize = widget.settings().iconTileSize.toDouble();
              // Просвет между плитками один и тот же по обеим осям, и он свой:
              // колоночный читается в сетке вдвое — он виден и вбок, и вниз
              // (`docs/spec/panel-view-icons.md`, §3).
              final gap = metrics.tileGap;
              final scaler = MediaQuery.textScalerOf(context);
              final nameStyle = IconTile.nameStyle(theme);
              final nameHeight = textLineHeight(nameStyle, scaler) * IconTile.nameLines;
              final tileHeight = IconTile.height(metrics, iconSize, nameHeight);

              // Поле вокруг содержимого — то же, что между плитками: крайняя
              // плитка отбита от рамы так же, как от соседки. Сверху к нему
              // добавлено место, которое раме давал отступ под плашкой пути:
              // вид занимает раму целиком, и без этого первый ряд оказался бы
              // под плашкой (`docs/spec/panel-views.md`, §3).
              final top = gap + metrics.panelTopPadding;
              final available = math.max(constraints.maxWidth - gap * 2, 1.0);
              final viewHeight = math.max(constraints.maxHeight, 1.0);

              // Ширина плитки — по самому длинному имени каталога, но не уже
              // плашки значка и не шире двадцати знаков. Считается **до** числа
              // столбцов, поэтому остаток места остаётся справа, а не
              // растягивает просветы (`docs/spec/panel-view-icons.md`, §3).
              final least = iconSize + (metrics.iconGap + metrics.cellPadding) * 2;
              final wanted = math.max(least, _widest.of(context, entries, style: nameStyle) + metrics.cellPadding * 4);
              // Потолок: место под имя сверх плашки значка. Спрошенное в
              // настройках или посчитанное от значка. Поля плитки и поля плашки
              // имени — те же четыре, по которым режется само имя.
              final asked = widget.settings().iconNameWidth;
              final room =
                  asked > PanelsSettings.autoNameWidth
                      ? asked.toDouble()
                      : (iconSize * _nameToIcon).clamp(_leastName, _mostName);
              final most = math.max(least, room + metrics.cellPadding * 4);
              // Панель уже плитки — плитка сжимается до панели: один столбец
              // лучше, чем ноль.
              final tileWidth = math.min(wanted, math.max(least, math.min(most, available)));
              final columns = math.max(1, ((available + gap) / (tileWidth + gap)).floor());
              final rowHeight = tileHeight + gap;
              final total = entries.isEmpty ? 0 : (entries.length / columns).ceil();

              final visible = math.max(1, (viewHeight / rowHeight).floor());
              panel.pageSize = (columns * visible).clamp(1, 10000);
              // Сетка: вбок курсор шагает на плитку, вниз — на целый ряд.
              panel.cursorSteps = PanelSteps.grid(columns);

              // Ширину окна изменили — плитки переехали в другие ряды, а
              // прокрутка осталась в точках и указывает уже не туда. Держимся
              // за курсор: он и есть то место, на которое человек смотрит.
              final resized = _columns != columns || _rowHeight != rowHeight || _viewHeight != viewHeight;
              final wasCursorAt = _cursorRowOnScreen();
              _columns = columns;
              _tileWidth = tileWidth;
              _tileHeight = tileHeight;
              _rowHeight = rowHeight;
              _gap = gap;
              _top = top;
              _headroom = metrics.pathHeaderHeight / 2;
              _viewHeight = viewHeight;
              if (resized) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _pinCursorRow(wasCursorAt));
              }

              // Курсор мог уехать за край чужими руками — стрелкой, поиском,
              // сменой каталога. Проверяется после разметки: до неё прокрутки
              // ещё нет.
              if (_lastCursorIndex != panel.cursorIndex) {
                _lastCursorIndex = panel.cursorIndex;
                WidgetsBinding.instance.addPostFrameCallback((_) => _revealCursor());
              }

              // Список **рядов** постоянной высоты: краткий вид, повёрнутый на
              // 90°. Кадр строит десятки плиток, а не тысячи
              // (`docs/widgets.md`, §4).
              final list = ListView.builder(
                controller: _scroll,
                // Поля — внутри прокрутки: так плитки уезжают под плашку пути
                // целиком, а не обрезаются по её краю.
                padding: EdgeInsets.fromLTRB(gap, top, gap, gap),
                itemExtent: rowHeight,
                itemCount: total,
                itemBuilder: (context, row) {
                  final first = row * columns;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    // Просветом ряда, а не полем у каждой плитки: поле висело
                    // бы и за последней, и ряд оказывался бы шире отведённого —
                    // на тот самый просвет. Раньше его съедало поле панели, а
                    // теперь съедать нечем, и раскладка честно ругается.
                    spacing: gap,
                    children: [
                      for (var column = 0; column < columns && first + column < entries.length; column++)
                        SizedBox(
                          width: tileWidth,
                          height: tileHeight,
                          // Плитку можно утащить — тем же жестом и по тому же
                          // правилу, что строку в таблице (`panel_drag.dart`).
                          child: panelDragSource(
                            context: context,
                            panel: panel,
                            entry: entries[first + column],
                            child: IconTile(
                              entry: entries[first + column],
                              iconSize: iconSize,
                              nameHeight: nameHeight,
                              width: tileWidth,
                              marked: panel.isMarked(entries[first + column]),
                              underCursor: panel.cursorIndex == first + column,
                              // Тот же вопрос, что задаёт плашка пути: горит
                              // курсор там, где сейчас клавиши.
                              panelActive: takesKeysHere(context, panel),
                              contentOf: panel.contentOf,
                              onTap: () => _onTap(first + column),
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
                // Слой пометки стоит **всегда**, а не появляется вместе с
                // жестом: строение дерева посреди работы мышью меняться не
                // вправе (`spec/drag-and-drop.md`).
                child: Listener(
                  onPointerDown: _marking.down,
                  onPointerMove: _marking.move,
                  onPointerUp: _marking.up,
                  onPointerCancel: _marking.up,
                  child: NotificationListener<ScrollEndNotification>(
                    // Прокрутка запоминается, когда устоялась: с неё вид и
                    // начнёт, когда его соберут заново.
                    onNotification: (notification) {
                      if (_shown) {
                        panel.setScrollOffset(notification.metrics.pixels);
                      }
                      _shown = true;
                      return false;
                    },
                    child: list,
                  ),
                ),
              );
            },
          ),
    );
  }
}
