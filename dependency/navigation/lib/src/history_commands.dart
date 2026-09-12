import 'package:fc_ui_api/fc_ui_api.dart';

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
