import 'package:fc_api/fc_api.dart';
import 'package:fc_history/fc_history.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сборка без модуля истории (`docs/spec/operation-history.md`, §5).
///
/// Модуль необязателен, как и все прочие: без него приложение собирается и
/// работает, а журнал не ведётся вовсе.
void main() {
  test('без модуля истории приложение живёт, и журнала нет', () async {
    final runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', size: 10),
        FakeEntry.directory('/dest'),
      ])..home = '/home',
      modules: const [Navigation(), Panels(), FileOps()],
    );
    await runtime.app.start();

    // Службы нет — и никто её не ждёт.
    expect(runtime.app.history, isNull);
    expect(runtime.commands.find(UndoCommand.commandId), isNull, reason: 'команды отмены в сборке нет');
    expect(runtime.commands.find(ShowHistoryCommand.commandId), isNull);

    // А работы идут как ни в чём не бывало.
    final operation = runtime.app.runOperation();
    await operation.run(
      OperationSpec(
        kind: FileOperations.copy,
        targets: const Targets.paths(['/home/notes.txt']),
        destination: const Destination.path('/dest'),
      ),
    );

    expect(runtime.app.left.entries, isNotEmpty);
  });
}
