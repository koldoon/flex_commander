import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_table_row.dart';
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

  final ScrollController _scroll = ScrollController();

  /// Раскладка последней отрисовки: по ней прокрутка держит курсор на виду ещё
  /// до того, как случится следующая.
  double _columnWidth = 0;
  double _viewWidth = 0;
  int _rows = 1;

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
    final column = widget.panel.cursorIndex ~/ _rows;
    final left = column * _columnWidth;
    final right = left + _columnWidth;
    final offset = _scroll.offset;
    final target = switch (0) {
      _ when left < offset => left,
      _ when right > offset + _viewWidth => right - _viewWidth,
      _ => offset,
    };
    if (target != offset) {
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    }
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
              _rows = rows;
              _columnWidth = columnWidth;
              _viewWidth = available;

              // Курсор мог уехать за край чужими руками — стрелкой, поиском,
              // сменой каталога. Проверяется после разметки: до неё прокрутки
              // ещё нет.
              if (_lastCursorIndex != panel.cursorIndex) {
                _lastCursorIndex = panel.cursorIndex;
                WidgetsBinding.instance.addPostFrameCallback((_) => _revealCursor());
              }

              final widths = <double>[iconWidth, math.max(columnWidth - iconWidth, 1)];

              return ListView.builder(
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
                    ],
                  );
                },
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
