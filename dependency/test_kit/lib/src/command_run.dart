import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Запуск команды из виджетного теста, где время поддельное.
///
/// Команда, ходящая за границу, идёт по настоящему циклу событий: ядро
/// отвечает не в этом кадре, а на следующем его обороте, — а внутри `pump` он
/// не крутится вовсе. Обычный `await` поэтому встал бы насмерть: тест держит
/// поддельное время и настоящему не отдаёт ни оборота.
extension CommandTesterRun on WidgetTester {
  /// Выполняет команду по настоящему времени и дорисовывает то, что вышло.
  Future<void> runCommand(AppCommand command, [Map<String, Object?> parameters = const {}]) async {
    await runAsync(() => command.executeWith(parameters));
    await pumpAndSettle();
  }
}
