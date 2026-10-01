import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'request_dialog.dart';

/// Окно, которым приложение сообщает о том, чего не предусмотрело.
///
/// Показывается по одному признаку — есть ли непоказанная ошибка, — и потому
/// живёт рядом со слоем команд, а не в нём: исключение прилетает откуда
/// угодно, в том числе из работы, у которой окна нет вовсе.
///
/// Рама и таблица те же, что у справки: пользователю неоткуда знать, что это
/// другое окно, и выглядеть оно должно так же.
class ErrorLayer extends StatelessWidget {
  const ErrorLayer({super.key, required this.errors, required this.toasts, required this.view});

  final Errors errors;
  final Toasts toasts;

  /// Стопка окон: необработанная ошибка — окно в ней, верхнего уровня и без
  /// родителя (`docs/spec/child-dialogs.md`, §4.5): закрытие любого другого
  /// окна не должно унести её непрочитанной.
  final ApplicationView view;

  @override
  Widget build(BuildContext context) {
    return RequestDialog<ErrorReport>(
      view: view,
      listenable: errors,
      current: () => errors.current,
      childOfTop: false,
      // Заголовок говорит, сколько ждёт в очереди, — сменился счёт, меняется и
      // окно.
      identity: (report) => '${report.time.microsecondsSinceEpoch}#${errors.pending}',
      spec: (context, report, _) {
        final pending = errors.pending;
        return DialogSpec(
          title:
              pending > 1
                  ? context.strings.tr('Unexpected error (1 of {count})', args: {'count': pending})
                  : context.strings.tr('Unexpected error'),
          takesFocus: true,
          // Enter и Esc делают одно: закрыть. Соглашаться тут не с чем.
          onSubmit: errors.dismiss,
          onDismiss: errors.dismiss,
          content: _ErrorDialog(
            report: report,
            onReport: () async {
              final said = context.strings.tr('Error report copied');
              if (await errors.copyReport()) {
                toasts.show(said);
              }
            },
          ),
        );
      },
    );
  }
}

class _ErrorDialog extends StatelessWidget {
  const _ErrorDialog({required this.report, required this.onReport});

  final ErrorReport report;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return FcKeyValueTable(
      sections: _sections(context.strings),
      actions: [FcButton(label: context.strings.tr('Report'), onPressed: onReport)],
    );
  }

  List<FcTableSection> _sections(Strings strings) => [
    FcTableSection(strings.tr('Error'), [
      FcTableRow(strings.tr('Type'), report.type),
      FcTableRow(strings.tr('Message'), report.message),
      FcTableRow(strings.tr('Time'), report.time.toIso8601String()),
      if (report.repeats > 1)
        FcTableRow(strings.tr('Repeated'), strings.plural(report.repeats, one: '{n} time', other: '{n} times')),
      if (report.context case final context?) FcTableRow(strings.tr('While'), context),
    ]),
    FcTableSection(strings.tr('Stack'), [FcTableRow('', report.stack?.toString() ?? strings.tr('No stack trace'))]),
  ];
}
