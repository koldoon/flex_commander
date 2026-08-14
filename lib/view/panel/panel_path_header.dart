import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// «Плашка» с текущим путём: скруглённый прямоугольник, наполовину заходящий
/// на верхнюю рамку панели.
class PanelPathHeader extends StatelessWidget {
  const PanelPathHeader({super.key, required this.path, required this.active});

  final String path;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final padding = metrics.cellPadding * 2;

    return Tooltip(
      message: path,
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        height: metrics.pathHeaderHeight,
        padding: EdgeInsets.symmetric(horizontal: padding),
        // Без alignment: иначе Container растянулся бы на всю доступную
        // ширину, а плашка должна облегать путь.
        decoration: BoxDecoration(
          color: active ? colors.pathActiveBackground : colors.pathInactiveBackground,
          border: Border.all(color: active ? colors.pathActiveBorder : colors.pathInactiveBorder),
          borderRadius: BorderRadius.circular(metrics.pathHeaderRadius),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final style = theme.pathStyle;
            return Text(
              _trimHead(path, style, constraints.maxWidth, MediaQuery.textScalerOf(context)),
              maxLines: 1,
              softWrap: false,
              style: style,
            );
          },
        ),
      ),
    );
  }

  /// Обрезает путь **слева**: конец строки важнее — в нём текущий каталог.
  ///
  /// Считается вручную, а не через `TextOverflow.ellipsis`: тот всегда режет
  /// хвост, а разворот направления текста ломает порядок символов в пути.
  static String _trimHead(String value, TextStyle style, double maxWidth, TextScaler scaler) {
    if (maxWidth.isInfinite || maxWidth <= 0) {
      return value;
    }

    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    if (widthOf(value) <= maxWidth) {
      return value;
    }

    // Двоичный поиск самого длинного хвоста, который помещается вместе с «…».
    var low = 0;
    var high = value.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (widthOf('…${value.substring(middle)}') <= maxWidth) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return '…${value.substring(low)}';
  }
}
