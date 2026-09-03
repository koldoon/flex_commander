import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

import 'find_files_form.dart';
import 'find_files_results.dart';
import 'find_files_state.dart';

/// Окно поиска по дереву — в две фазы.
///
/// Сперва спрашивают, что искать; потом показывают, что нашлось. Это два разных
/// окна, и команда их показывает: строить окна — её дело, а решать, когда
/// какое, — дело состояния (`spec/file-search.md`, §3).
class FindFilesCommand extends AppCommand {
  static const String commandId = 'search.findFiles';

  /// Маска: задают параметром — окно параметров тогда не показывается вовсе.
  static const String maskParam = 'mask';

  /// Сколько поисков уже заводили: из этого собирается имя работы.
  ///
  /// Поисков может идти сколько угодно — ровно как копирований, — и у каждого
  /// своя полоска в статусной области. Разводит их этот счётчик.
  static int _runs = 0;

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
  bool isExecutable(CommandContext context) => context.panel.path.isNotEmpty && !context.panel.busy;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final where = panel.path;
    if (where.isEmpty) {
      return;
    }

    final app = context.app;
    final state = FindFilesState(app: app, panel: panel, where: where, runId: '$commandId#${++_runs}');

    // Окна показывает команда, а состояние их только зовёт. Каждое закрывает
    // за собой предыдущее: два окна поиска разом на экране — это два вопроса,
    // на которые человек отвечает одновременно.
    state.showParams =
        () => _show(app, state, title: label, content: FindFilesForm(state: state), onSubmit: state.begin);
    state.showResults =
        () => _show(
          app,
          state,
          title: '$label: "${state.query.mask}"',
          content: FindFilesResults(state: state),
          onSubmit: () => unawaited(state.submit()),
        );

    final given = context.invocation.param<String>(maskParam);
    if (given == null) {
      state.showParams!();
      return;
    }

    // Маску дали параметром — спрашивать не о чем: сразу находки и обход.
    state.typed(given);
    await state.begin();
  }

  /// Показывает окно фазы и запоминает, чем его закрыть.
  void _show(
    Application app,
    FindFilesState state, {
    required String title,
    required Widget content,
    required VoidCallback onSubmit,
  }) {
    late final String dialogId;
    state.close = () => app.view.closeDialog(dialogId);
    dialogId = app.view.showDialog(
      DialogSpec(
        title: title,
        takesFocus: true,
        // Ширину окна назначают сами фазы, долей экрана: иначе рама мерила бы
        // содержимое, а ленивый список находок на вопрос о своей ширине не
        // отвечает вовсе.
        ownWidth: true,
        content: content,
        onSubmit: onSubmit,
        // `Esc` во время обхода прекращает его, а не закрывает окно: найденное
        // при этом остаётся, и уйти можно вторым нажатием.
        onDismiss: () {
          if (state.busy) {
            state.stop();
            return;
          }
          state.finish();
        },
      ),
    );
  }
}
