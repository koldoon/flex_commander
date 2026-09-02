import 'package:fc_api/fc_api.dart';

import 'fs_node.dart';

/// Узел значением — то, чем его рисуют по ту сторону границы.
///
/// Путь у «..» пустой нарочно: псевдострока показывает **чужой** каталог —
/// тот, куда ведёт, — и запомненная по его пути подменяла бы собой настоящий.
/// За этот урок уже заплачено (`spec/isolated-core.md`, §4.3.2).
FileEntry entryValueOf(FsNode node) {
  final file = node is FileNode ? node : null;
  return FileEntry(
    name: node.name,
    kind: switch (node) {
      ParentDirNode() => EntryKind.parent,
      DirectoryNode() => EntryKind.directory,
      LinkNode() => EntryKind.link,
      _ => EntryKind.file,
    },
    path: node is ParentDirNode ? '' : node.pathString,
    directoryPath: node.parentDirectory?.displayPath ?? '',
    size: node.size,
    modified: file?.modified,
    created: file?.created,
    accessed: file?.accessed,
    attributes: file?.attributes ?? const FileAttributes.unknown(),
    executable: file?.executable ?? false,
    broken: file?.broken ?? false,
    linkToDirectory: node is LinkNode && node.isDirectoryLink,
    reference: node is LinkNode ? node.reference : '',
    scheme: node is ParentDirNode ? '' : node.provider.scheme,
  );
}
