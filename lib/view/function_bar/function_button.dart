import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Кнопка нижней панели: номер клавиши слева и подпись команды в кнопке.
class FunctionButton extends StatelessWidget {
  const FunctionButton({super.key, required this.number, required this.label, this.enabled = true, this.onPressed});

  /// Номер функциональной клавиши: 1 для F1.
  final int number;

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final active = enabled && onPressed != null;

    return Row(
      children: [
        Padding(
          padding: EdgeInsets.only(right: metrics.cellPadding / 2),
          child: Text('F$number', style: theme.rowStyle.copyWith(color: colors.secondaryText)),
        ),
        Expanded(
          child: MouseRegion(
            cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: active ? onPressed : null,
              child: Opacity(
                opacity: active ? 1 : 0.5,
                child: Container(
                  height: metrics.functionButtonHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [colors.buttonTop, colors.buttonBottom],
                    ),
                    border: Border.all(color: colors.buttonBorder),
                    borderRadius: BorderRadius.circular(metrics.functionButtonRadius),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: theme.rowStyle.copyWith(color: colors.buttonText),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
