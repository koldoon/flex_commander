import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../state/commands/app_command.dart';
import '../theme/app_theme.dart';

/// Окна запущенных команд.
///
/// Ядро рисует рамку, заголовок и затемнение, а содержимое берёт у самой
/// команды — [AppCommand.getDialog]. Так все окна выглядят одинаково, но
/// команда полностью распоряжается тем, что внутри, и меняет это по ходу
/// работы: ввод, ход выполнения, вопрос, ошибка.
class CommandDialogLayer extends StatelessWidget {
  const CommandDialogLayer({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.commands,
      builder: (context, _) {
        final dialogs = app.commands.openDialogs;
        if (dialogs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            for (final command in dialogs)
              if (command.getDialog(context) case final content?)
                _CommandDialogFrame(key: ValueKey(command.runId), title: command.label, child: content),
          ],
        );
      },
    );
  }
}

/// Рамка окна команды: затемнение, заголовок, содержимое.
class _CommandDialogFrame extends StatelessWidget {
  const _CommandDialogFrame({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;

    return Stack(
      children: [
        // Затемнение: пока окно открыто, работать с панелями нельзя.
        const Positioned.fill(child: ModalBarrier(dismissible: false, color: Color(0x66000000))),
        Center(
          child: FocusScope(
            autofocus: true,
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.panelBackground,
                border: Border.all(color: colors.panelBorder),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      title,
                      style: theme.headerStyle.copyWith(
                        fontSize: theme.metrics.fontSize + 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
