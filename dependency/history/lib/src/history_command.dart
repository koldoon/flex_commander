import 'package:fc_ui_api/fc_ui_api.dart';

import 'history_dialog.dart';
import 'undo_command.dart';

/// Показать, что приложение сделало за сеанс
/// (`docs/spec/operation-history.md`, §10).
///
/// Своей клавиши нет: `Cmd-Shift-Z` во всём мире значит «повторить», а повтора
/// здесь не будет. Открывают окно из палитры и щелчком по полосе фоновых
/// работ.
class ShowHistoryCommand extends AppCommand {
  ShowHistoryCommand(this.history);

  static const String commandId = 'history.show';

  final OperationHistory history;

  @override
  String get id => commandId;

  @override
  String get label => tr('Operation history');

  @override
  String get description => tr('What the application did to files this session');

  @override
  Set<String> get keywords => const {'undo', 'journal', 'log'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final view = app.view;
    late final String dialogId;

    final state = HistoryDialogState(
      history: history,
      strings: app.strings,
      // Отмена — та же команда, что и по `Cmd-Z`: второго пути к откату быть
      // не должно, иначе окно и клавиша однажды разойдутся.
      undo: () async => app.commands.runAndWait(UndoCommand.commandId),
    );
    state.close = () => view.closeDialog(dialogId);

    dialogId = view.showDialog(
      DialogSpec(
        title: tr('Operation history'),
        id: commandId,
        resizable: true,
        takesFocus: true,
        ownWidth: true,
        content: HistoryDialogForm(state: state),
        onSubmit: state.submit,
        onDismiss: state.close,
      ),
    );
  }
}
