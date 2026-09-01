import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Две панели и перетаскиваемый разделитель между ними.
class SplitView extends StatefulWidget {
  const SplitView({
    super.key,
    required this.left,
    required this.right,
    required this.ratio,
    required this.onRatioChanged,
    required this.onCenter,
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

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
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
        final available = constraints.maxWidth - metrics.areaGap;
        final minRatio = (metrics.minPanelWidth / available).clamp(0.0, 0.5);
        final leftWidth = available * widget.ratio.clamp(minRatio, 1 - minRatio);

        // Ширина захвата: зазор бывает уже, чем палец, — тогда область шире его
        // самого и заходит на края обеих панелей.
        final handleWidth = math.max(metrics.resizeHandleWidth, metrics.areaGap);

        return Stack(
          children: [
            Row(
              children: [
                SizedBox(width: leftWidth, child: widget.left),
                SizedBox(width: metrics.areaGap, height: double.infinity),
                Expanded(child: widget.right),
              ],
            ),
            // Захват — **поверх** панелей, а не внутри зазора.
            //
            // Раньше он лежал внутри и расширялся `OverflowBox`: нарисовано
            // шире, а нажатия за пределами зазора до него не доходили —
            // проверка попадания идёт по размеру родителя, и всё, что вылезло,
            // она отбрасывает. Пока зазор был в восемь точек, разницы никто не
            // замечал; ужали до шести — и мимо стало попадать заметно.
            Positioned(
              left: leftWidth + (metrics.areaGap - handleWidth) / 2,
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
