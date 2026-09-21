import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Окна наборов выбора: имя и подтверждение
/// (`docs/spec/settings-presets.md`, §6).

/// Спросить имя набора.
///
/// Занятое имя — ошибка **в том же окне**, а не молчаливая перезапись: набор,
/// затёртый другим набором того же имени, теряется без следа.
Future<void> askPresetName(
  Application app, {
  required String title,
  required String submitLabel,
  required String initial,
  required String? Function(String name) save,
}) {
  final view = app.view;
  final closed = Completer<void>();
  late final String dialogId;
  void close() {
    view.closeDialog(dialogId);
    if (!closed.isCompleted) {
      closed.complete();
    }
  }

  final state = _NameState(initial: initial);
  state.close = close;
  state.save = save;

  dialogId = view.showDialog(
    DialogSpec(
      title: title,
      takesFocus: true,
      content: _NameForm(state: state, submitLabel: submitLabel),
      onSubmit: state.submit,
      onDismiss: close,
    ),
  );
  return closed.future;
}

/// Спросить согласия — и ничего не делать без него.
Future<void> askConfirm(
  Application app, {
  required String title,
  required String message,
  required String confirmLabel,
  required VoidCallback onConfirm,
}) {
  final view = app.view;
  final closed = Completer<void>();
  late final String dialogId;
  void close() {
    view.closeDialog(dialogId);
    if (!closed.isCompleted) {
      closed.complete();
    }
  }

  dialogId = view.showDialog(
    DialogSpec(
      title: title,
      takesFocus: true,
      content: CommandDialogConfirm(
        message: message,
        confirmLabel: confirmLabel,
        onCancel: close,
        onConfirm: () {
          close();
          onConfirm();
        },
      ),
      onSubmit: () {
        close();
        onConfirm();
      },
      onDismiss: close,
    ),
  );
  return closed.future;
}

/// Что набрано в окне имени и чем кончилась попытка сохранить.
class _NameState extends ChangeNotifier {
  _NameState({required this.initial}) : name = initial;

  final String initial;

  String name;
  String error = '';

  late final VoidCallback close;

  /// Вернуть текст ошибки — или null, если получилось.
  late final String? Function(String name) save;

  void submit() {
    final complaint = save(name.trim());
    if (complaint == null) {
      close();
      return;
    }
    error = complaint;
    notifyListeners();
  }
}

class _NameForm extends StatefulWidget {
  const _NameForm({required this.state, required this.submitLabel});

  final _NameState state;
  final String submitLabel;

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  late final TextEditingController _name = TextEditingController(text: widget.state.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.state.initial.length);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder:
          (context, _) => CommandDialogForm(
            onCancel: state.close,
            onSubmit: state.submit,
            submitLabel: widget.submitLabel,
            error: state.error.isEmpty ? null : state.error,
            children: [
              CommandDialogField(
                label: context.strings.tr('Name'),
                child: FcTextField(
                  controller: _name,
                  autofocus: true,
                  onChanged: (value) => state.name = value,
                  onSubmitted: (_) => state.submit(),
                ),
              ),
            ],
          ),
    );
  }
}
