import 'package:fc_api/fc_api.dart';
import 'package:fc_history/fc_history.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Отмена через настоящее ядро: заявка туда, работа там.
void main() {
  test('откат создания каталога доходит до конца через ядро', () async {
    final provider = InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home';
    final AppRuntime runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();

    // Создаём каталог так же, как это делает F7.
    final making = runtime.app.runOperation();
    await making.run(
      const OperationSpec(
        kind: FileOperations.makeDirectory,
        destination: Destination.path('/home'),
        options: {FileOperations.name: '111'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final history = runtime.app.history!;
    debugPrint(
      'записей: ${history.all.length}, журнал: ${history.last?.journal.length}, помеха: ${history.undoObstacle}',
    );

    final undoing = runtime.app.runOperation();
    await undoing
        .run(
          OperationSpec(
            kind: HistoryOperations.undo,
            options: {
              HistoryOperations.journal: [for (final entry in history.last!.journal) entry.toMap()],
            },
          ),
        )
        .timeout(const Duration(seconds: 5), onTimeout: () => throw StateError('откат завис'));

    expect(await provider.resolvePath().run('/home/111'), isNull);
  });
}
