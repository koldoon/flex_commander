import 'package:fc_ui_api/fc_ui_api.dart';

/// Запуск команды напрямую — короткий путь для теста.
///
/// В приложении команду запускает реестр: он собирает [CommandContext] по
/// состоянию приложения и вызову. Тесту это состояние собирать незачем — он уже
/// держит приложение, к которому команда привязана.
extension CommandTestRun on AppCommand {
  /// Выполняет команду так, как если бы её вызвали с этими значениями.
  Future<void> executeWith([Map<String, Object?> parameters = const {}]) =>
      execute(CommandContext.of(appOrNull!, CommandInvocation(parameters: parameters)));
}
