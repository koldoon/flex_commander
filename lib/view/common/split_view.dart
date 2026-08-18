import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Две панели и перетаскиваемый разделитель между ними.
class SplitView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - metrics.panelGap;
        final minRatio = (metrics.minPanelWidth / available).clamp(0.0, 0.5);
        final leftWidth = available * ratio.clamp(minRatio, 1 - minRatio);

        return Row(
          children: [
            SizedBox(width: leftWidth, child: left),
            SizedBox(
              width: metrics.panelGap,
              height: double.infinity,
              // Зазор между панелями узкий, поэтому область захвата шире его
              // самого и заходит на края обеих панелей.
              child: OverflowBox(
                maxWidth: math.max(metrics.resizeHandleWidth, metrics.panelGap),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) {
                      onRatioChanged((leftWidth + details.delta.dx) / available);
                    },
                    // Двойной клик и щелчок средней кнопкой возвращают панели
                    // к равной ширине: одно действие — один путь.
                    onDoubleTap: onCenter,
                    onTertiaryTapUp: (_) => onCenter(),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
