import '../serialization.dart';
import '../tree/fs_node.dart';
import 'column_spec.dart';

enum SortDirection {
  ascending,
  descending;

  SortDirection get opposite => this == ascending ? descending : ascending;
}

/// Правило сортировки списка панели.
class SortSpec {
  const SortSpec({this.column = FsColumn.name, this.direction = SortDirection.ascending, this.foldersFirst = true});

  final FsColumn column;
  final SortDirection direction;

  /// Каталоги всегда выше файлов, независимо от колонки и направления.
  final bool foldersFirst;

  /// Клик по заголовку: та же колонка — смена направления, другая — она же
  /// по возрастанию.
  SortSpec toggled(FsColumn other) {
    if (other == column) {
      return SortSpec(column: column, direction: direction.opposite, foldersFirst: foldersFirst);
    }
    return SortSpec(column: other, direction: SortDirection.ascending, foldersFirst: foldersFirst);
  }

  Map<String, Object?> toJson() => {'column': column.name, 'direction': direction.name, 'foldersFirst': foldersFirst};

  /// Разбор настроек: непонятные значения заменяются умолчаниями, а не роняют
  /// загрузку.
  factory SortSpec.fromJson(Object? json) {
    if (json is! Map) {
      return const SortSpec();
    }
    const fallback = SortSpec();
    // Значения читаются конверторами пакета; перечислимые типы он не знает,
    // поэтому имя колонки и направление сводятся к допустимым здесь.
    final column = FsColumn.byName(extract('', json['column']));

    return SortSpec(
      column: column != null && column.sortable ? column : fallback.column,
      direction:
          extract('', json['direction']) == SortDirection.descending.name
              ? SortDirection.descending
              : SortDirection.ascending,
      foldersFirst: extract(fallback.foldersFirst, json['foldersFirst']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SortSpec && other.column == column && other.direction == direction && other.foldersFirst == foldersFirst;

  @override
  int get hashCode => Object.hash(column, direction, foldersFirst);

  @override
  String toString() => 'SortSpec(${column.name}, ${direction.name})';
}

/// Компаратор для правила сортировки.
///
/// Порядок проверок: псевдоузел «..» всегда первый, затем — каталоги перед
/// файлами, и только после этого сравнение по колонке. Первые два правила
/// не переворачиваются направлением сортировки.
int Function(FsNode, FsNode) comparatorFor(SortSpec spec) {
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

    var result = _compareByColumn(a, b, spec.column);
    if (result == 0) {
      // Доводчик по имени: без него порядок «плавает» между перечитываниями.
      result = naturalCompare(a.name, b.name);
      return spec.direction == SortDirection.ascending ? result : -result;
    }
    return spec.direction == SortDirection.ascending ? result : -result;
  };
}

bool _isDirectory(FsNode node) => node is DirectoryNode || (node is LinkNode && node.isDirectoryLink);

int _compareByColumn(FsNode a, FsNode b, FsColumn column) {
  return switch (column) {
    FsColumn.name => naturalCompare(a.name, b.name),
    FsColumn.ext => naturalCompare(_extensionOf(a), _extensionOf(b)),
    FsColumn.attributes => naturalCompare(_attributesOf(a), _attributesOf(b)),
    FsColumn.size => a.size.compareTo(b.size),
    FsColumn.modified => _compareDates(_fileOf(a)?.modified, _fileOf(b)?.modified),
    FsColumn.created => _compareDates(_fileOf(a)?.created, _fileOf(b)?.created),
    FsColumn.accessed => _compareDates(_fileOf(a)?.accessed, _fileOf(b)?.accessed),
    FsColumn.icon => _typeOf(a).index.compareTo(_typeOf(b).index),
  };
}

FileNode? _fileOf(FsNode node) => node is FileNode ? node : null;

String _extensionOf(FsNode node) => _fileOf(node)?.extension ?? '';

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

/// Сравнение строк «по-человечески»: без учёта регистра и с числами как
/// числами, чтобы `file2` шёл перед `file10`.
int naturalCompare(String a, String b) {
  final lowerA = a.toLowerCase();
  final lowerB = b.toLowerCase();

  var i = 0;
  var j = 0;
  while (i < lowerA.length && j < lowerB.length) {
    final charA = lowerA.codeUnitAt(i);
    final charB = lowerB.codeUnitAt(j);

    if (_isDigit(charA) && _isDigit(charB)) {
      final startA = i;
      final startB = j;
      while (i < lowerA.length && _isDigit(lowerA.codeUnitAt(i))) {
        i++;
      }
      while (j < lowerB.length && _isDigit(lowerB.codeUnitAt(j))) {
        j++;
      }

      final numberA = lowerA.substring(startA, i);
      final numberB = lowerB.substring(startB, j);
      final result = _compareNumbers(numberA, numberB);
      if (result != 0) {
        return result;
      }
      continue;
    }

    if (charA != charB) {
      return charA < charB ? -1 : 1;
    }
    i++;
    j++;
  }

  final rest = (lowerA.length - i).compareTo(lowerB.length - j);
  if (rest != 0) {
    return rest;
  }
  // Строки различаются только регистром: сравниваем как есть, чтобы порядок
  // оставался устойчивым.
  return a.compareTo(b);
}

/// Числа сравниваются по значению, ведущие нули не важны; при равенстве
/// короче — раньше, поэтому `file01` и `file1` не считаются одинаковыми.
int _compareNumbers(String a, String b) {
  final trimmedA = a.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final trimmedB = b.replaceFirst(RegExp(r'^0+(?=\d)'), '');

  if (trimmedA.length != trimmedB.length) {
    return trimmedA.length < trimmedB.length ? -1 : 1;
  }
  final result = trimmedA.compareTo(trimmedB);
  if (result != 0) {
    return result;
  }
  return a.length.compareTo(b.length);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
