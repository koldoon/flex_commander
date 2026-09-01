import 'dart:async';

import 'package:fc_api/fc_api.dart';

import 'find_files_form.dart';
import 'find_files_state.dart';

/// Окно поиска по дереву.
class FindFilesCommand extends AppCommand {
  static const String commandId = 'search.findFiles';

  /// Маска: задают параметром — окно тогда не открывается вовсе.
  static const String maskParam = 'mask';

  @override
  String get id => commandId;

  @override
  String get label => 'Find files';

  @override
  String get description => 'Search the tree below the current directory by name mask';

  @override
  Set<String> get keywords => const {'search', 'locate', 'mask', 'wildcard'};

  /// Искать можно там, где есть каталог: в архиве и по `ssh` — тоже, обход
  /// идёт через провайдера.
  @override
  bool isExecutable(CommandContext context) => context.panel.directory != null && !context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final where = panel.directory;
    if (where == null) {
      return;
    }

    final view = context.app.view;
    final state = FindFilesState(panel: panel, where: where);
    final given = context.invocation.param<String>(maskParam);
    if (given != null) {
      state.typed(given);
    }

    late final String dialogId;
    state.close = () => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: label,
        takesFocus: true,
        // Ширину окно назначает себе само — долей экрана, как окно копирования.
        // Иначе рама мерила бы содержимое, а вместе с ним и таблицу находок: от
        // длинных путей окно прыгало бы на каждой пачке находок, а ленивый
        // список на вопрос о своей ширине не отвечает вовсе.
        ownWidth: true,
        content: FindFilesForm(state: state),
        // `Enter` в открытом окне разбирает рама, а не поле ввода: без этого
        // окно на него не отвечало вовсе, и оставалось только закрыть его.
        onSubmit: () => unawaited(state.submit()),
        // `Esc` во время обхода прекращает его, а не закрывает окно: найденное
        // при этом остаётся, и уйти можно вторым нажатием.
        onDismiss: () {
          if (state.busy) {
            state.stop();
            return;
          }
          state.close?.call();
        },
      ),
    );

    // Маску дали параметром — искать сразу: окно открыли не затем, чтобы её
    // ещё раз подтверждать.
    if (given != null) {
      await state.start();
    }
  }
}
