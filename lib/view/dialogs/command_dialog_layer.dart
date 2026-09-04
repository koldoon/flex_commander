import 'package:flutter/material.dart';

import 'package:fc_ui_api/fc_ui_api.dart';

import 'dialog_frame.dart';

/// Окна запущенных команд.
///
/// Ядро рисует рамку, заголовок и затемнение, а всё остальное берёт из
/// описания, которое даёт показавший окно, — [DialogSpec]. Так все окна выглядят одинаково, но
/// команда полностью распоряжается тем, что внутри, и меняет это по ходу
/// работы: ввод, ход выполнения, вопрос, ошибка.
class CommandDialogLayer extends StatelessWidget {
  const CommandDialogLayer({super.key, required this.app});

  final Application app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.view,
      builder: (context, _) {
        final own = app.view.dialogs;
        if (own.isEmpty) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            for (final spec in own)
              DialogFrame(
                key: ValueKey(spec),
                title: spec.title,
                takesFocus: spec.takesFocus,
                area: spec.area,
                placement: spec.placement,
                ownWidth: spec.ownWidth,
                onSubmit: spec.onSubmit ?? () {},
                onDismiss: spec.onDismiss ?? () {},
                child: spec.content,
              ),
          ],
        );
      },
    );
  }
}
