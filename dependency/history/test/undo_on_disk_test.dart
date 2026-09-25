import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_history/fc_history.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Отмена на настоящей файловой системе.
void main() {
  late Directory temp;
  late LocalTreeProvider provider;
  late ProviderRegistry registry;
  late CollectedJournal journal;
  const engine = TreeTransferEngine();

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fc_undo');
    provider = LocalTreeProvider(homePath: temp.path, readInIsolate: false);
    registry = ProviderRegistry(root: provider);
    journal = CollectedJournal();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('откат создания каталога доходит до конца', () async {
    final root = await provider.resolvePath().run(temp.path) as DirectoryNode;
    await engine.makeDirectory().run(MakeDirectoryParams(root, '111', journal: journal));
    expect(Directory('${temp.path}/111').existsSync(), isTrue);
    debugPrint('в журнале: ${[for (final e in journal.entries) e.toMap()]}');

    final work = UndoWork(strings: StringsRegistry(), registry: registry).operation();
    await work
        .run(
          OperationInputs(
            targets: const [],
            destination: null,
            editor: engine,
            options: {
              HistoryOperations.journal: [for (final entry in journal.entries) entry.toMap()],
            },
            onFound: (_) {},
          ),
        )
        .timeout(const Duration(seconds: 5));

    expect(Directory('${temp.path}/111').existsSync(), isFalse);
  });
}
