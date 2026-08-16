import 'package:flutter/material.dart';

import '../../model/async/operation_request.dart';
import '../theme/app_theme.dart';

/// Готовые куски содержимого окна команды.
///
/// Рамку и заголовок рисует ядро, а внутренности — команда. Чтобы окна разных
/// команд выглядели одинаково, типовые случаи собраны здесь: форма с полем
/// ввода, подтверждение, ход выполнения и вопрос по ходу работы.

/// Форма: произвольное содержимое, кнопки «отмена» и подтверждение.
class CommandDialogForm extends StatelessWidget {
  const CommandDialogForm({
    super.key,
    required this.child,
    required this.onCancel,
    required this.onSubmit,
    required this.submitLabel,
    this.error,
    this.busy = false,
  });

  final Widget child;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final String submitLabel;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        if (error != null) _CommandDialogError(message: error!),
        _CommandDialogActions(
          actions: [
            _CommandDialogAction(label: 'Cancel', onPressed: onCancel),
            _CommandDialogAction(label: submitLabel, onPressed: busy ? null : onSubmit, primary: true),
          ],
        ),
      ],
    );
  }
}

/// Подтверждение действия.
class CommandDialogConfirm extends StatelessWidget {
  const CommandDialogConfirm({
    super.key,
    required this.message,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.error,
  });

  final String message;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: theme.rowStyle),
        if (error != null) _CommandDialogError(message: error!),
        _CommandDialogActions(
          actions: [
            _CommandDialogAction(label: 'Cancel', onPressed: onCancel),
            _CommandDialogAction(label: confirmLabel, onPressed: onConfirm, primary: true),
          ],
        ),
      ],
    );
  }
}

/// Ход выполнения с возможностью прервать.
class CommandDialogProgress extends StatelessWidget {
  const CommandDialogProgress({super.key, required this.message, required this.onCancel, this.progress});

  final String message;
  final double? progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: theme.rowStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress, minHeight: 4),
        _CommandDialogActions(actions: [_CommandDialogAction(label: 'Cancel', onPressed: onCancel)]),
      ],
    );
  }
}

/// Вопрос по ходу работы: столько кнопок, сколько вариантов ответа.
class CommandDialogQuestion extends StatelessWidget {
  const CommandDialogQuestion({super.key, required this.message, required this.options, required this.onAnswer});

  final String message;
  final List<OperationOption> options;
  final void Function(OperationOption option) onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: theme.rowStyle),
        _CommandDialogActions(
          actions: [
            for (final option in options)
              _CommandDialogAction(
                label: option.label,
                onPressed: () => onAnswer(option),
                primary: option == options.first,
              ),
          ],
        ),
      ],
    );
  }
}

class _CommandDialogError extends StatelessWidget {
  const _CommandDialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(message, style: theme.rowStyle.copyWith(color: theme.colors.error)),
    );
  }
}

class _CommandDialogActions extends StatelessWidget {
  const _CommandDialogActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // Wrap, а не Row: кнопок бывает три, и с длинными названиями («Delete
    // permanently», «Skip all») в одну строку они не помещаются.
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
    );
  }
}

/// Кнопка окна команды: вид один на все окна.
class _CommandDialogAction extends StatelessWidget {
  const _CommandDialogAction({required this.label, required this.onPressed, this.primary = false});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton(onPressed: onPressed, child: Text(label));
    }
    return TextButton(onPressed: onPressed, child: Text(label));
  }
}
