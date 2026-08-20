import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'dialog_frame.dart';

/// Окно, которым приложение спрашивает пароль.
///
/// Спрашивает не команда, а тот, кто наткнулся на защищённое: провайдер архива,
/// а позже — подключение к серверу. Поэтому окно живёт не в слое команд, а
/// рядом с ним, и рисуется по одному признаку — есть ли неотвеченный запрос.
///
/// Рама та же, что у окон команд ([DialogFrame]): заголовок, затемнение, Enter
/// и Esc. Пользователю неоткуда знать, что этот вопрос задаёт не команда, и
/// выглядеть он должен так же.
class CredentialsLayer extends StatelessWidget {
  const CredentialsLayer({super.key, required this.credentials});

  final Credentials credentials;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: credentials,
      builder: (context, _) {
        final request = credentials.pending;
        if (request == null) {
          return const SizedBox.shrink();
        }

        return _CredentialsDialog(
          // Ключ по адресу: следующий вопрос — про другой архив, и поля должны
          // быть пустыми, а не с чужим набранным.
          key: ValueKey('${request.realm}#${request.retry}'),
          request: request,
          onAnswer: credentials.answer,
        );
      },
    );
  }
}

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({super.key, required this.request, required this.onAnswer});

  final CredentialRequest request;
  final void Function(Credential? credential) onAnswer;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late final Map<String, TextEditingController> _inputs = {
    for (final field in widget.request.fields) field.name: TextEditingController(),
  };

  @override
  void dispose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  void _submit() => widget.onAnswer(Credential({for (final entry in _inputs.entries) entry.key: entry.value.text}));

  void _dismiss() => widget.onAnswer(null);

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final request = widget.request;

    return DialogFrame(
      title: request.title,
      // Фокус ставит первое поле: спрашивают пароль — значит, его сейчас и
      // будут набирать.
      takesFocus: true,
      onSubmit: _submit,
      onDismiss: _dismiss,
      child: CommandDialogForm(
        error: request.retry ? 'Wrong password' : null,
        onCancel: _dismiss,
        onSubmit: _submit,
        submitLabel: 'Unlock',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(request.message, style: theme.dialogTextStyle),
            SizedBox(height: metrics.dialogGap),
            for (final field in request.fields) ...[
              if (field != request.fields.first) SizedBox(height: metrics.dialogGap),
              CommandDialogField(
                label: field.label,
                child: FcTextField(
                  controller: _inputs[field.name]!,
                  autofocus: field == request.fields.first,
                  obscureText: field.secret,
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
