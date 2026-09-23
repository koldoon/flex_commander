import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'in_memory_tree_provider.dart';

/// Архив ядровым модулем: файл `.arc` открывается каталогом.
///
/// Настоящий упаковщик для этого не нужен — важно лишь, что у файла есть схема
/// и что монтирование даёт дерево. Так проверяются и вход в архив, и ветвь
/// архива в дереве (`docs/spec/panel-view-tree.md`, §4б).
class FakeArchiveMount implements FcBackendModule {
  const FakeArchiveMount([this.entries = defaultEntries]);

  /// Что лежит внутри архива. По умолчанию — каталог и файл рядом.
  final List<FakeEntry> Function() entries;

  static List<FakeEntry> defaultEntries() => [
    FakeEntry.directory('/inner'),
    FakeEntry.file('/inner/doc.txt', content: [1, 2, 3]),
    FakeEntry.file('/readme.md', content: [4]),
  ];

  @override
  String get id => 'test.archive_mount';

  @override
  String get title => 'Arc archives';

  @override
  void installBackend(BackendRegistry registry) {
    registry.provider(
      'arc',
      () => TaskOperation<FsNode, TreeProvider>((op, host) async => InMemoryArchiveProvider(entries(), host)),
      extensions: {'arc'},
    );
  }
}
