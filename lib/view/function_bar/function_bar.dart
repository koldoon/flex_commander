import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'function_button.dart';

/// Ряд функциональных кнопок внизу окна.
///
/// Пока подписи заданы списком — как в референсном `Main.mxml`. На этапе
/// клавиатуры их источником станет реестр команд: одна и та же команда должна
/// стоять и за кнопкой, и за клавишей.
class FunctionBar extends StatelessWidget {
  const FunctionBar({super.key});

  static const List<String> labels = ['Help', 'Menu', 'View', 'Edit', 'Copy', 'Move', 'Mk Dir', 'Delete', '-', '-'];

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;

    return SizedBox(
      height: metrics.functionBarHeight,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) SizedBox(width: metrics.functionBarGap),
            Expanded(
              child: FunctionButton(
                number: i + 1,
                label: labels[i],
                // Команд ещё нет — кнопки показаны, но не работают.
                enabled: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
