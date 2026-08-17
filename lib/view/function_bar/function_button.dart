import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Кнопка нижней панели: номер клавиши слева и подпись команды в кнопке.
///
/// Повторяет `FunctionKeyRenderer` референса: номер вынесен наружу и стоит
/// вплотную к кнопке справа, сама кнопка — скруглённый прямоугольник цвета
/// `sea`, нажатие затемняет её.
class FunctionButton extends StatefulWidget {
  const FunctionButton({super.key, required this.number, required this.label, this.enabled = true, this.onPressed});

  /// Номер функциональной клавиши: 1 для F1.
  final int number;

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  State<FunctionButton> createState() => _FunctionButtonState();
}

class _FunctionButtonState extends State<FunctionButton> {
  bool _pressed = false;

  bool get _active => widget.enabled && widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;

    return Opacity(
      opacity: _active ? 1 : 0.5,
      child: Row(
        children: [
          SizedBox(
            width: metrics.functionKeyNumberWidth,
            child: Text(
              // В референсе стояла голая цифра; `F1` понятнее и совпадает с тем,
              // что написано на клавише.
              'F${widget.number}',
              textAlign: TextAlign.right,
              style: theme.uiStyle.copyWith(color: colors.functionKeyNumber),
            ),
          ),
          SizedBox(width: metrics.functionKeyNumberGap),
          Expanded(
            child: MouseRegion(
              cursor: _active ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _active ? (_) => setState(() => _pressed = true) : null,
                onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
                onTapCancel: _active ? () => setState(() => _pressed = false) : null,
                onTap: _active ? widget.onPressed : null,
                child: Container(
                  height: metrics.functionButtonHeight,
                  padding: EdgeInsets.only(left: metrics.functionKeyNumberGap, right: metrics.cellPadding),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: colors.functionButtonBackground,
                    borderRadius: BorderRadius.circular(metrics.functionButtonRadius),
                  ),
                  foregroundDecoration:
                      _pressed
                          ? BoxDecoration(
                            color: colors.buttonPressed,
                            borderRadius: BorderRadius.circular(metrics.functionButtonRadius),
                          )
                          : null,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: theme.uiStyle.copyWith(color: colors.functionButtonText),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
