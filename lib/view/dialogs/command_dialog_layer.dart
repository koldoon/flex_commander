import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';

import 'dialog_frame.dart';

/// Окна запущенных команд.
///
/// Ядро рисует рамку, заголовок и затемнение, а всё остальное берёт из
/// описания, которое даёт сама команда, — [AppCommand.dialogSpec]. Так все окна выглядят одинаково, но
/// команда полностью распоряжается тем, что внутри, и меняет это по ходу
/// работы: ввод, ход выполнения, вопрос, ошибка.
class CommandDialogLayer extends StatelessWidget {
  const CommandDialogLayer({super.key, required this.app});

  final Application app;

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
              if (command.dialogSpec(context) case final spec?)
                DialogFrame(
                  key: ValueKey(command.runId),
                  title: spec.title,
                  takesFocus: spec.takesFocus,
                  area: spec.area,
                  onSubmit: command.submit,
                  onDismiss: command.dismiss,
                  child: spec.content,
                ),
          ],
        );
      },
    );
  }
}
