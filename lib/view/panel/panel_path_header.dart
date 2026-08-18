import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';

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

    // Активность панели в референсе плашкой не показывалась, но панелей две:
    // видеть, какая из них принимает клавиши, нужно, и приглушённая плашка —
    // самый спокойный способ это сказать.
    final style = active ? theme.pathStyle : theme.pathStyle.copyWith(color: colors.pathInactiveText);

    return Tooltip(
      message: path,
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        height: metrics.pathHeaderHeight,
        padding: EdgeInsets.symmetric(horizontal: metrics.labelPadding),
        // Без alignment: иначе Container растянулся бы на всю доступную
        // ширину, а плашка должна облегать путь.
        decoration: BoxDecoration(
          color: active ? colors.pathBackground : colors.pathInactiveBackground,
          border: Border.all(color: colors.pathBorder, width: metrics.strokeWidth),
          borderRadius: BorderRadius.circular(metrics.pathHeaderRadius),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              widthFactor: 1,
              // Сдвига, как в строках списка, здесь нет: он нужен Consolas,
              // а путь набран Ubuntu — у него базовая линия обычная.
              child: Text(
                _trimHead(path, style, constraints.maxWidth, MediaQuery.textScalerOf(context)),
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: style,
              ),
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
