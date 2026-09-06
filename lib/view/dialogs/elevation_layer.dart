import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'dialog_frame.dart';

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
  const ElevationLayer({super.key, required this.elevation});

  final Elevation elevation;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: elevation,
      builder: (context, _) {
        final request = elevation.pending;
        if (request == null) {
          return const SizedBox.shrink();
        }

        return DialogFrame(
          key: ValueKey('${request.realm}#${request.path}'),
          title: context.strings.tr('Administrator rights'),
          takesFocus: false,
          onSubmit: () => elevation.answer(true),
          onDismiss: () => elevation.answer(false),
          child: CommandDialogConfirm(
            // Место названо всегда, даже когда это своя машина: записать
            // `/etc/hosts` от администратора здесь и на чужом сервере — разные
            // по последствиям вещи, и различать их надо глазами.
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
