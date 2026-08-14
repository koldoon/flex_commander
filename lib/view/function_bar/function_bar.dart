import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../state/commands/app_command.dart';
import '../theme/app_theme.dart';
import 'function_button.dart';

/// Ряд функциональных кнопок внизу окна.
///
/// Подписи и доступность берутся из реестра команд: за кнопкой и за клавишей
/// стоит одна и та же команда, поэтому они не могут разойтись.
class FunctionBar extends StatelessWidget {
  const FunctionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    final app = AppScope.of(context);

    return SizedBox(
      height: metrics.functionBarHeight,
      child: ListenableBuilder(
        // Доступность кнопок зависит от состояния активной панели: есть ли
        // объект под курсором, не занята ли панель.
        listenable: Listenable.merge([app.left, app.right]),
        builder:
            (context, _) => Row(
              children: [
                for (final slot in FunctionKeySlot.values) ...[
                  if (slot.index > 0) SizedBox(width: metrics.functionBarGap),
                  Expanded(child: _button(app.commands.commandForSlot(slot), slot)),
                ],
              ],
            ),
      ),
    );
  }

  Widget _button(AppCommand? command, FunctionKeySlot slot) {
    if (command == null) {
      return FunctionButton(number: slot.number, label: '-', enabled: false);
    }
    return Builder(
      builder: (context) {
        final registry = AppScope.read(context).commands;
        return FunctionButton(
          number: slot.number,
          label: command.label,
          enabled: registry.isExecutable(command),
          onPressed: () => registry.run(command),
        );
      },
    );
  }
}
