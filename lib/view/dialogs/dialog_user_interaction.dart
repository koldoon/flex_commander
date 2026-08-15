import 'package:flutter/material.dart';

import '../../model/app/user_interaction.dart';
import '../theme/app_theme.dart';

/// Диалоги приложения — реализация [UserInteraction] поверх Flutter.
///
/// Владеет ключом навигатора: команды выполняются вне дерева виджетов, и
/// показать диалог им иначе неоткуда.
class DialogUserInteraction implements UserInteraction {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  BuildContext? get _context => navigatorKey.currentContext;

  @override
  Future<String?> promptText({
    required String title,
    String initialText = '',
    String? hint,
    String confirmLabel = 'OK',
  }) async {
    final context = _context;
    if (context == null) {
      return null;
    }

    return showDialog<String>(
      context: context,
      builder:
          (context) =>
              _TextPromptDialog(title: title, initialText: initialText, hint: hint, confirmLabel: confirmLabel),
    );
  }

  @override
  Future<bool> confirm({required String title, String? message, String confirmLabel = 'OK'}) async {
    final context = _context;
    if (context == null) {
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => _MessageDialog(title: title, message: message, confirmLabel: confirmLabel, showCancel: true),
    );
    return result ?? false;
  }

  @override
  Future<void> showError({required String title, String? message}) async {
    final context = _context;
    if (context == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _MessageDialog(title: title, message: message, confirmLabel: 'OK', isError: true),
    );
  }
}

/// Диалог ввода строки: Enter подтверждает, Esc отменяет.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.initialText, required this.confirmLabel, this.hint});

  final String title;
  final String initialText;
  final String confirmLabel;
  final String? hint;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isEmpty) {
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return AlertDialog(
      title: Text(widget.title, style: theme.headerStyle.copyWith(fontSize: theme.metrics.fontSize + 2)),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _text,
          autofocus: true,
          style: theme.rowStyle,
          decoration: InputDecoration(hintText: widget.hint, isDense: true),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class _MessageDialog extends StatelessWidget {
  const _MessageDialog({
    required this.title,
    required this.confirmLabel,
    this.message,
    this.showCancel = false,
    this.isError = false,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final bool showCancel;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final message = this.message;

    return AlertDialog(
      title: Text(
        title,
        style: theme.headerStyle.copyWith(
          fontSize: theme.metrics.fontSize + 2,
          color: isError ? theme.colors.error : null,
        ),
      ),
      content: message == null ? null : SizedBox(width: 360, child: Text(message, style: theme.rowStyle)),
      actions: [
        if (showCancel) TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(confirmLabel)),
      ],
    );
  }
}
