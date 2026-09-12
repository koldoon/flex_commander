import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';

import 'history_dialog.dart';

/// Назад по шагам этой сессии.
///
/// История у каждого набора своя: ходит по дереву он, ему и помнить
/// (`docs/spec/session-history.md`). Показали набор в другой панели — «назад»
/// там ведёт по его шагам, а не по тому, что видела эта сторона.
class GoBackCommand extends AppCommand {
  static const String commandId = 'panel.history.back';

  @override
  String get id => commandId;

  @override
  String get label => tr('Back');

  @override
  String get description => tr('Return to the previous directory of this panel');

  @override
  Set<String> get keywords => const {'history', 'previous', 'go back'};

  /// Некуда идти — команда приглушена, а не молчит: нажатие без ответа это
  /// ошибка (`docs/widgets.md`).
  @override
  bool isExecutable(CommandContext context) => !context.session.busy && context.session.canGoBack;

  @override
  Future<void> execute(CommandContext context) => context.session.goBack();
}

/// Вперёд — если до этого возвращались.
class GoForwardCommand extends AppCommand {
  static const String commandId = 'panel.history.forward';

  @override
  String get id => commandId;

  @override
  String get label => tr('Forward');

  @override
  String get description => tr('Go forward again after going back');

  @override
  Set<String> get keywords => const {'history', 'next', 'go forward'};

  @override
  bool isExecutable(CommandContext context) => !context.session.busy && context.session.canGoForward;

  @override
  Future<void> execute(CommandContext context) => context.session.goForward();
}

/// Пройденное этой сессией — списком, с прыжком к любому шагу.
///
/// Показывает **всю** историю, а не только пройденное назад: выше отмеченного
/// шага — «вперёд», ниже — «назад», и по соседям видно, куда поведут стрелки
/// (`docs/spec/session-history.md`, §9).
class ChooseHistoryCommand extends AppCommand {
  static const String commandId = 'panel.history.choose';

  @override
  String get id => commandId;

  @override
  String get label => tr('History');

  @override
  String get description => tr('Show where this panel has been');

  @override
  Set<String> get keywords => const {'visited', 'recent directories', 'where i have been'};

  /// Одному шагу список не нужен: в нём было бы то самое место, где и стоим.
  @override
  bool isExecutable(CommandContext context) =>
      !context.session.busy && (context.session.canGoBack || context.session.canGoForward);

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    // Список спрашивается сейчас, а не едет в каждом снимке: он нужен ровно
    // здесь, один раз на открытие окна.
    final walked = await panel.history();
    if (walked.steps.isEmpty) {
      return;
    }

    final state = HistoryDialogState(panel: panel, steps: walked.steps, current: walked.index);
    final view = context.app.view;
    // Окно встаёт над своей панелью: история у каждой своя, и вставать оно
    // должно там, куда поведёт (`docs/spec/dialog-placement.md`, §3).
    final ratio = context.app.splitRatio;
    final area = identical(panel, context.app.left) ? DialogArea(end: ratio) : DialogArea(start: ratio);
    late final String dialogId;
    state.close = () => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: 'History',
        // Над своей панелью: история у каждой своя, и окно должно вставать
        // там, куда оно поведёт (`docs/spec/dialog-placement.md`).
        area: area,
        takesFocus: true,
        ownWidth: true,
        content: HistoryDialogForm(state: state),
        onSubmit: () => unawaited(state.submit()),
        onDismiss: state.close,
      ),
    );
  }
}
