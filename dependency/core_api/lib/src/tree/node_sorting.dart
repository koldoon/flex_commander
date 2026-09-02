import 'package:fc_api/fc_api.dart';

import 'fs_node.dart';

/// Компаратор для правила сортировки.
///
/// Само правило ([SortSpec]) — общее значение: его выбирают на экране и
/// сохраняют в настройках. Сравнение живёт здесь, где живут узлы.
///
/// Порядок проверок: псевдоузел «..» всегда первый, затем — каталоги перед
/// файлами, и только после этого сравнение по колонке. Первые два правила
/// не переворачиваются направлением сортировки.
int Function(FsNode, FsNode) comparatorFor(SortSpec spec, {FileNaming naming = const ReferenceFileNaming()}) {
  return (a, b) {
    if (a is ParentDirNode) {
      return b is ParentDirNode ? 0 : -1;
    }
    if (b is ParentDirNode) {
      return 1;
    }

    if (spec.foldersFirst) {
      final aDir = _isDirectory(a);
      final bDir = _isDirectory(b);
      if (aDir != bDir) {
        return aDir ? -1 : 1;
      }
    }

    var result = _compareByColumn(a, b, spec.column, naming);
    if (result == 0) {
      // Доводчик по имени: без него порядок «плавает» между перечитываниями.
      result = naturalCompare(a.name, b.name);
      return spec.direction == SortDirection.ascending ? result : -result;
    }
    return spec.direction == SortDirection.ascending ? result : -result;
  };
}

bool _isDirectory(FsNode node) => node is DirectoryNode || (node is LinkNode && node.isDirectoryLink);

/// Каталог объекта — тем же текстом, каким он показан в колонке пути.
String _directoryOf(FsNode node) => node.parentDirectory?.displayPath ?? '';

int _compareByColumn(FsNode a, FsNode b, FsColumn column, FileNaming naming) {
  return switch (column) {
    FsColumn.name => naturalCompare(a.name, b.name),
    FsColumn.path => naturalCompare(_directoryOf(a), _directoryOf(b)),
    FsColumn.ext => naturalCompare(_extensionOf(a, naming), _extensionOf(b, naming)),
    FsColumn.attributes => naturalCompare(_attributesOf(a), _attributesOf(b)),
    FsColumn.size => a.size.compareTo(b.size),
    FsColumn.modified => _compareDates(_fileOf(a)?.modified, _fileOf(b)?.modified),
    FsColumn.created => _compareDates(_fileOf(a)?.created, _fileOf(b)?.created),
    FsColumn.accessed => _compareDates(_fileOf(a)?.accessed, _fileOf(b)?.accessed),
    FsColumn.icon => _typeOf(a).index.compareTo(_typeOf(b).index),
  };
}

FileNode? _fileOf(FsNode node) => node is FileNode ? node : null;

/// Расширение для сортировки — тем же правилом, что рисует колонку.
///
/// Иначе показ и порядок разойдутся: имя стояло бы в списке под одним
/// расширением, а сортировалось по другому.
String _extensionOf(FsNode node, FileNaming naming) => _fileOf(node) == null ? '' : naming.split(node.name).extension;

String _attributesOf(FsNode node) => _fileOf(node)?.attributes.modeString ?? '';

_TypeOrder _typeOf(FsNode node) {
  if (node is DirectoryNode) return _TypeOrder.directory;
  if (node is LinkNode) {
    return node.isDirectoryLink ? _TypeOrder.directory : _TypeOrder.link;
  }
  return _TypeOrder.file;
}

enum _TypeOrder { directory, link, file }

/// Отсутствующая дата меньше любой заданной.
int _compareDates(DateTime? a, DateTime? b) {
  if (a == null) {
    return b == null ? 0 : -1;
  }
  if (b == null) {
    return 1;
  }
  return a.compareTo(b);
}
