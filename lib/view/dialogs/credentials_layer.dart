import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'request_dialog.dart';

/// Окно, которым приложение спрашивает пароль.
///
/// Спрашивает не команда, а тот, кто наткнулся на защищённое: провайдер архива,
/// подключение к серверу. Окно кладётся в общую стопку, дочерним к верхнему
/// окну — обычно это окно работы, которая и наткнулась
/// (`docs/spec/child-dialogs.md`, §4.5). Закрыли его — вопрос снимается
/// отказом, а не висит.
///
/// Пользователю неоткуда знать, что этот вопрос задаёт не команда, и
/// выглядеть он должен так же.
class CredentialsLayer extends StatelessWidget {
  const CredentialsLayer({super.key, required this.credentials, required this.view});

  final CredentialPrompt credentials;

  final ApplicationView view;

  @override
  Widget build(BuildContext context) {
    return RequestDialog<CredentialRequest>(
      view: view,
      listenable: credentials,
      current: () => credentials.pending,
      // По адресу и попытке: следующий вопрос — про другой архив или после
      // неверного пароля, и поля должны быть пустыми, а не с чужим набранным.
      identity: (request) => '${request.realm}#${request.retry}',
      spec: (context, request, parent) {
        final form = GlobalKey<_CredentialsDialogState>();
        return DialogSpec(
          parent: parent,
          // Заголовок приходит значением — от того, кто спросил: он живёт в
          // ядре и по-русски говорить не обязан. Переводит тот, кто показывает
          // (`docs/spec/localization.md`, §3).
          title: context.strings.tr(request.title),
          // Фокус ставит первое поле: спрашивают пароль — значит, его сейчас
          // и будут набирать.
          takesFocus: true,
          onSubmit: () => form.currentState?._submit(),
          onDismiss: () => credentials.answer(null),
          content: _CredentialsDialog(key: form, request: request, onAnswer: credentials.answer),
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
    final request = widget.request;

    return CommandDialogForm(
      error: request.retry ? context.strings.tr('Wrong password') : null,
      onCancel: _dismiss,
      onSubmit: _submit,
      submitLabel: context.strings.tr('Unlock'),
      children: [
        CommandDialogField.wide(child: Text(request.message, style: theme.dialogTextStyle)),
        for (final field in request.fields)
          CommandDialogField(
            label: context.strings.tr(field.label),
            child: FcTextField(
              controller: _inputs[field.name]!,
              autofocus: field == request.fields.first,
              obscureText: field.secret,
              onSubmitted: (_) => _submit(),
            ),
          ),
      ],
    );
  }
}
