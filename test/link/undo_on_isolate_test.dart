import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_history/fc_history.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Создание каталога и откат — на настоящем изоляте и настоящей файловой
/// системе: журнал едет через настоящий порт, работа идёт в настоящем ядре.
void main() {
  late AppRuntime runtime;
  late Directory temp;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('fc_undo_live');
    runtime = await initIsolated(frontendModules(), overrides: AppOverrides(window: FakeWindowService()));
  });

  tearDown(() async {
    await runtime.dispose();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  test('создали каталог и отменили — работа доходит до конца', () async {
    await runtime.app.start();

    final making = runtime.app.runOperation();
    await making.run(
      OperationSpec(
        kind: FileOperations.makeDirectory,
        destination: Destination.path(temp.path),
        options: const {FileOperations.name: '111'},
      ),
    );
    expect(Directory('${temp.path}/111').existsSync(), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final history = runtime.app.history!;
    debugPrint(
      'записей: ${history.all.length}, журнал: ${history.last?.journal.length}, помеха: ${history.undoObstacle}',
    );
    debugPrint('записи: ${[for (final e in history.last?.journal ?? const []) e.toMap()]}');

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
        .timeout(const Duration(seconds: 10), onTimeout: () => throw StateError('откат завис'));

    expect(Directory('${temp.path}/111').existsSync(), isFalse);
  });
}
