import 'package:flutter/widgets.dart';

import 'fc_theme.dart';

/// Мини-пара панелей: где показан набор.
///
/// Левая ячейка горит — показан слева, правая — справа, обе — в обеих
/// (`docs/spec/panel-sessions.md`, §3). Погасшая не пропадает, а темнеет: пара
/// читается как две панели, и одна ячейка вместо двух означала бы другое.
///
/// Здесь, а не в ряду наборов: тем же знаком набор помечен и в окне выбора, а
/// два способа нарисовать одно и то же однажды разойдутся.
class FcSideMarks extends StatelessWidget {
  const FcSideMarks({super.key, required this.left, required this.right, this.leftKey, this.rightKey, this.dimColor});

  final bool left;
  final bool right;

  /// Ключи горящих ячеек — ставит **вызывающий**: по ним проверка узнаёт, в
  /// каком списке метка, в ряду или в окне. Общий ключ сделал бы находку
  /// двусмысленной, когда открыты оба.
  final Key? leftKey;
  final Key? rightKey;

  /// Цвет погасшей ячейки; null — цвет рамки панели.
  ///
  /// Его задаёт тот, кто знает свой фон. Рамка панели годится на фоне списка,
  /// но не везде: у тёмного оформления macOS она прозрачна, и на синей плашке
  /// набора погасшая ячейка пропадала совсем — пара читалась одной меткой.
  final Color? dimColor;

  /// Сколько места занимает.
  ///
  /// Объявляется наружу, потому что ряд наборов раздаёт ширину записям сам и
  /// обязан знать, сколько у него отняли (`panel_row.dart`). Та же величина
  /// держит и сам виджет — расходиться им негде.
  static double widthOf(FcTheme theme) => theme.metrics.markedBarWidth * 2 + theme.metrics.strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    // Высота — со строчную букву: метка стоит в строке, а не подпирает её края.
    Widget cell({required bool lit, required Key? key}) => SizedBox(
      width: theme.metrics.markedBarWidth,
      height: theme.metrics.iconSize,
      child: ColoredBox(
        color: lit ? theme.colors.markedBar : dimColor ?? theme.colors.panelBorder,
        key: lit ? key : null,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        cell(lit: left, key: leftKey),
        SizedBox(width: theme.metrics.strokeWidth),
        cell(lit: right, key: rightKey),
      ],
    );
  }
}
