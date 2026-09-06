import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'dialog_frame.dart';

/// Окно, которым приложение сообщает о том, чего не предусмотрело.
///
/// Показывается по одному признаку — есть ли непоказанная ошибка, — и потому
/// живёт рядом со слоем команд, а не в нём: исключение прилетает откуда
/// угодно, в том числе из работы, у которой окна нет вовсе.
///
/// Рама и таблица те же, что у справки: пользователю неоткуда знать, что это
/// другое окно, и выглядеть оно должно так же.
class ErrorLayer extends StatelessWidget {
  const ErrorLayer({super.key, required this.errors, required this.toasts});

  final Errors errors;

  /// Куда сказать, что отчёт скопирован: «случилось и закончилось» — это
  /// всплывающее сообщение, как и везде.
  final Toasts toasts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: errors,
      builder: (context, _) {
        final report = errors.current;
        if (report == null) {
          return const SizedBox.shrink();
        }

        return _ErrorDialog(
          // Ключ по времени: следующая ошибка — другая, и прокрутка стека не
          // должна остаться от предыдущей.
          key: ValueKey(report.time),
          report: report,
          pending: errors.pending,
          onClose: errors.dismiss,
          onReport: () async {
            // Строка берётся до ожидания: после него `context` уже нельзя
            // трогать, а сказать надо ровно то же самое.
            final said = context.strings.tr('Error report copied');
            if (await errors.copyReport()) {
              toasts.show(said);
            }
          },
        );
      },
    );
  }
}

class _ErrorDialog extends StatelessWidget {
  const _ErrorDialog({
    super.key,
    required this.report,
    required this.pending,
    required this.onClose,
    required this.onReport,
  });

  final ErrorReport report;

  /// Сколько ошибок ждёт, считая показанную.
  final int pending;

  final VoidCallback onClose;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return DialogFrame(
      // Счёт в заголовке — чтобы было видно, что за этой стоят ещё: одна
      // поломка часто тянет за собой соседние, и по первой судить рано.
      title:
          pending > 1
              ? context.strings.tr('Unexpected error (1 of {count})', args: {'count': pending})
              : context.strings.tr('Unexpected error'),
      takesFocus: true,
      // Enter и Esc делают одно: закрыть. Соглашаться тут не с чем.
      onSubmit: onClose,
      onDismiss: onClose,
      child: FcKeyValueTable(
        sections: _sections(context.strings),
        onClose: onClose,
        actions: [FcButton(label: context.strings.tr('Report'), onPressed: onReport)],
      ),
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
