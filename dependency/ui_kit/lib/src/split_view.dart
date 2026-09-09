import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fc_theme.dart';

/// Две области и перетаскиваемый разделитель между ними.
///
/// Мест, где тянут границу, два: между панелями окна и между столбцами
/// комбинированного вида (`docs/spec/panel-view-combined.md`, §7). Правило у
/// них одно, поэтому и разделитель один.
class FcSplitView extends StatefulWidget {
  const FcSplitView({
    super.key,
    required this.left,
    required this.right,
    required this.ratio,
    required this.onRatioChanged,
    required this.onCenter,
    this.minWidth,
    this.divider = false,
    this.gap,
  });

  final Widget left;
  final Widget right;

  /// Доля ширины, занимаемая левой панелью.
  final double ratio;

  final ValueChanged<double> onRatioChanged;

  /// Вернуть разделитель в середину.
  ///
  /// Отдельно от [onRatioChanged], хотя мог бы быть и `onRatioChanged(0.5)`:
  /// это не «поставь такую долю», а именованное действие, и снаружи за ним
  /// стоит команда. Знать о ней виджету незачем — как и о том, что «середина»
  /// это ровно половина.
  final VoidCallback onCenter;

  /// Сколько остаётся у каждой стороны как минимум; пусто — ширина панели из
  /// темы. Столбцам вида нужна своя: панель целиком туда не поместится.
  final double? minWidth;

  /// Ширина зазора между областями; пусто — зазор между панелями из темы.
  ///
  /// Внутри панели он равен самой линейке: по общему правилу подсветка строки
  /// упирается в границу, и просвет между курсором и чертой читался бы как
  /// сбой (`docs/spec/panel-view-combined.md`, §7).
  final double? gap;

  /// Рисовать ли линейку в зазоре.
  ///
  /// Между панелями её нет: у каждой своя рамка, и вторая черта между ними
  /// была бы лишней. Внутри панели — наоборот: столбцы стоят в одной рамке, и
  /// граница между ними читается той же линейкой, что и между колонками
  /// таблицы (`docs/spec/panel-view-combined.md`, §7).
  final bool divider;

  @override
  State<FcSplitView> createState() => _FcSplitViewState();
}

class _FcSplitViewState extends State<FcSplitView> {
  /// Насколько правее границы панелей взялись за разделитель.
  ///
  /// Запоминается на время перетаскивания, чтобы разделитель не прыгал под
  /// курсор в первое же движение: за него берутся не строго по центру.
  double _grab = 0;

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = widget.gap ?? metrics.areaGap;
        final available = constraints.maxWidth - gap;
        final minRatio = ((widget.minWidth ?? metrics.minPanelWidth) / available).clamp(0.0, 0.5);
        final leftWidth = available * widget.ratio.clamp(minRatio, 1 - minRatio);

        // Ширина захвата: зазор бывает уже, чем палец, — тогда область шире его
        // самого и заходит на края обеих панелей.
        final handleWidth = math.max(metrics.resizeHandleWidth, gap);

        return Stack(
          children: [
            Row(
              children: [
                SizedBox(width: leftWidth, child: widget.left),
                SizedBox(width: gap, height: double.infinity),
                Expanded(child: widget.right),
              ],
            ),
            // Линейка — под захватом: её видно, а тянут всё равно за него.
            if (widget.divider)
              Positioned(
                left: leftWidth + (gap - metrics.strokeWidth) / 2,
                top: 0,
                bottom: 0,
                width: metrics.strokeWidth,
                child: ColoredBox(color: FcTheme.of(context).colors.columnDivider),
              ),
            // Захват — **поверх** панелей, а не внутри зазора.
            //
            // Раньше он лежал внутри и расширялся `OverflowBox`: нарисовано
            // шире, а нажатия за пределами зазора до него не доходили —
            // проверка попадания идёт по размеру родителя, и всё, что вылезло,
            // она отбрасывает. Пока зазор был в восемь точек, разницы никто не
            // замечал; ужали до шести — и мимо стало попадать заметно.
            Positioned(
              left: leftWidth + (gap - handleWidth) / 2,
              top: 0,
              bottom: 0,
              width: handleWidth,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Доля считается от **положения курсора**, а не набегает
                  // из его смещений.
                  //
                  // Смещения приходят чаще, чем рисуются кадры, и все
                  // пришедшие за один кадр считались бы от одной и той же
                  // ширины — уцелело бы только последнее. Снаружи это
                  // выглядит так: разделитель ползёт в нужную сторону, но
                  // отстаёт от курсора и на быстром движении отстаёт сильно.
                  onHorizontalDragStart: (details) {
                    final position = _positionOf(context, details.globalPosition);
                    _grab = position == null ? 0 : position - leftWidth;
                  },
                  onHorizontalDragUpdate: (details) {
                    final position = _positionOf(context, details.globalPosition);
                    if (position != null) {
                      widget.onRatioChanged((position - _grab) / available);
                    }
                  },
                  // Двойной клик и щелчок средней кнопкой возвращают панели
                  // к равной ширине: одно действие — один путь.
                  onDoubleTap: widget.onCenter,
                  onTertiaryTapUp: (_) => widget.onCenter(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Где курсор внутри области с панелями, в её же координатах.
  ///
  /// `context` здесь — от `LayoutBuilder`, то есть от всей области целиком, а
  /// не от самого разделителя: тот во время перетаскивания едет, и считать от
  /// него значило бы мерить от подвижной точки.
  static double? _positionOf(BuildContext context, Offset global) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.globalToLocal(global).dx : null;
  }
}
