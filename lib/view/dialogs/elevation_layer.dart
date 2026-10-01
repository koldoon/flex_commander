import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'request_dialog.dart';

/// Окно, которым приложение спрашивает согласия на запись от администратора.
///
/// Спрашивает не команда, а тот, кто наткнулся на отказ: провайдер, которому не
/// дали записать. Поэтому окно живёт рядом со слоем команд и рисуется по одному
/// признаку — есть ли неотвеченное предложение.
///
/// **Спрашивается всегда**, даже когда пароль не нужен: запомненный ответ или
/// `NOPASSWD` не должны превращать запись в системный каталог в незаметное
/// действие.
class ElevationLayer extends StatelessWidget {
  const ElevationLayer({super.key, required this.elevation, required this.view});

  final Elevation elevation;

  /// Стопка окон: вопрос о правах — окно в ней, дочернее к верхнему окну —
  /// обычно к окну работы, которой отказали (`docs/spec/child-dialogs.md`,
  /// §4.5). Закрыли его — вопрос снимается отказом.
  final ApplicationView view;

  @override
  Widget build(BuildContext context) {
    return RequestDialog<ElevationRequest>(
      view: view,
      listenable: elevation,
      current: () => elevation.pending,
      identity: (request) => '${request.realm}#${request.path}',
      spec: (context, request, parent) {
        return DialogSpec(
          parent: parent,
          title: context.strings.tr('Administrator rights'),
          onSubmit: () => elevation.answer(true),
          onDismiss: () => elevation.answer(false),
          content: CommandDialogConfirm(
            message: context.strings.tr(
              '{action} {path}\non {where} as administrator?',
              args: {'action': context.strings.tr(request.action), 'path': request.path, 'where': request.where},
            ),
            confirmLabel: context.strings.tr('Continue'),
            onCancel: () => elevation.answer(false),
            onConfirm: () => elevation.answer(true),
          ),
        );
      },
    );
  }
}
