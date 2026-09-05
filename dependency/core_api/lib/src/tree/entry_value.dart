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
    // Настоящий путь есть только у настоящей файловой системы: внутри архива
    // и на сервере имя объекта вне приложения ничего не значит.
    //
    // У «..» он **есть**, в отличие от [FileEntry.path]. Разница не в
    // придирчивости: пустой `path` бережёт опознание строки — по нему её
    // запоминают, и чужой адрес подменял бы настоящий каталог. `realPath` же
    // ничего не опознаёт, он отвечает на другой вопрос — «что эта строка
    // значит вне приложения», — а «..» ведёт во вполне настоящий каталог, и
    // система знает о нём столько же, сколько о любом другом.
    realPath: !node.provider.capabilities.realFileSystem ? '' : node.pathString,
  );
}
