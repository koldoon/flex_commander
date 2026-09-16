import 'dart:async';
import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'cursor_pin.dart';
import 'icon_tile.dart';
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

  /// Сколько места имя вправе занять сверх значка: вдвое от его стороны.
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

    final top = row * _rowHeight;
    final bottom = top + _rowHeight;
    final target = switch (0) {
      _ when top < offset => top,
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
    return (widget.panel.cursorIndex ~/ _columns) * _rowHeight - _scroll.offset;
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
    final target = (widget.panel.cursorIndex ~/ _columns) * _rowHeight - was;
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
    final column = (local.dx / _step).floor();
    final row = ((local.dy + offset) / _rowHeight).floor();
    if (column < 0 || column >= _columns || row < 0) {
      return null;
    }
    final index = row * _columns + column;
    return index >= 0 && index < widget.panel.entries.length ? index : null;
  }

  /// Шаг сетки вбок: плитка и просвет за ней.
  double get _step => _tileWidth + _gap;

  double _gap = 0;

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
      (index % _columns) * _step,
      (index ~/ _columns) * _rowHeight - offset,
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
              // Просвет между плитками один и тот же по обеим осям — тот же,
              // каким отбиты колонки списка. Своей метрики темы не заводится:
              // каждая новая величина тянет за собой правку макета и сверку
              // (`docs/spec/design-system.md`).
              final gap = metrics.columnGap;
              final scaler = MediaQuery.textScalerOf(context);
              final nameHeight = textLineHeight(theme.rowStyle, scaler) * IconTile.nameLines;
              final tileHeight = IconTile.height(metrics, iconSize, nameHeight);

              final inset = metrics.panelRightPadding;
              final available = math.max(constraints.maxWidth - inset, 1.0);

              // Ширина плитки — по самому длинному имени каталога, но не уже
              // плашки значка и не шире двадцати знаков. Считается **до** числа
              // столбцов, поэтому остаток места остаётся справа, а не
              // растягивает просветы (`docs/spec/panel-view-icons.md`, §3).
              final least = iconSize + (metrics.iconGap + metrics.cellPadding) * 2;
              final wanted = math.max(
                least,
                _widest.of(context, entries, style: theme.rowStyle) + metrics.cellPadding * 4,
              );
              // Потолок: место под имя сверх плашки значка. Поля плитки и поля
              // плашки имени — те же четыре, по которым режется само имя.
              final most = math.max(
                least,
                (iconSize * _nameToIcon).clamp(_leastName, _mostName) + metrics.cellPadding * 4,
              );
              // Панель уже плитки — плитка сжимается до панели: один столбец
              // лучше, чем ноль.
              final tileWidth = math.min(wanted, math.max(least, math.min(most, available)));
              final columns = math.max(1, ((available + gap) / (tileWidth + gap)).floor());
              final rowHeight = tileHeight + gap;
              final total = entries.isEmpty ? 0 : (entries.length / columns).ceil();

              final visible = math.max(1, (constraints.maxHeight / rowHeight).floor());
              panel.pageSize = (columns * visible).clamp(1, 10000);
              // Сетка: вбок курсор шагает на плитку, вниз — на целый ряд.
              panel.cursorSteps = PanelSteps.grid(columns);

              // Ширину окна изменили — плитки переехали в другие ряды, а
              // прокрутка осталась в точках и указывает уже не туда. Держимся
              // за курсор: он и есть то место, на которое человек смотрит.
              final resized = _columns != columns || _rowHeight != rowHeight || _viewHeight != constraints.maxHeight;
              final wasCursorAt = _cursorRowOnScreen();
              _columns = columns;
              _tileWidth = tileWidth;
              _tileHeight = tileHeight;
              _rowHeight = rowHeight;
              _gap = gap;
              _viewHeight = constraints.maxHeight;
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
                itemExtent: rowHeight,
                itemCount: total,
                itemBuilder: (context, row) {
                  final first = row * columns;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var column = 0; column < columns && first + column < entries.length; column++)
                        Padding(
                          padding: EdgeInsets.only(right: gap),
                          child: SizedBox(
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
              );
            },
          ),
    );
  }
}
