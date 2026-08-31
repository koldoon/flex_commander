import '../util/file_name.dart';
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

int _compareByColumn(FsNode a, FsNode b, FsColumn column, FileNaming naming) {
  return switch (column) {
    FsColumn.name => naturalCompare(a.name, b.name),
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

/// Сравнение строк «по-человечески»: без учёта регистра и с числами как
/// числами, чтобы `file2` шёл перед `file10`.
///
/// Работает по кодам символов, не выделяя ни одной строки: сравнение зовётся
/// на каждую пару при сортировке, и десять тысяч имён дают около четверти
/// миллиона вызовов. Прежняя запись приводила обе строки к нижнему регистру
/// **внутри** сравнения и разбирала числа регулярным выражением — на десяти
/// тысячах записей сортировка стоила дороже самого чтения каталога.
int naturalCompare(String a, String b) {
  var i = 0;
  var j = 0;

  while (i < a.length && j < b.length) {
    final charA = a.codeUnitAt(i);
    final charB = b.codeUnitAt(j);

    if (_isDigit(charA) && _isDigit(charB)) {
      var endA = i;
      var endB = j;
      while (endA < a.length && _isDigit(a.codeUnitAt(endA))) {
        endA++;
      }
      while (endB < b.length && _isDigit(b.codeUnitAt(endB))) {
        endB++;
      }

      final result = _compareNumbers(a, i, endA, b, j, endB);
      if (result != 0) {
        return result;
      }
      i = endA;
      j = endB;
      continue;
    }

    if (charA != charB) {
      // Регистр приводится только у разошедшихся символов: у совпавших он и
      // так одинаков, а приводить всю строку — значит выделять её заново.
      final lowerA = _toLower(charA);
      final lowerB = _toLower(charB);
      if (lowerA != lowerB) {
        return lowerA < lowerB ? -1 : 1;
      }
    }
    i++;
    j++;
  }

  final rest = (a.length - i).compareTo(b.length - j);
  if (rest != 0) {
    return rest;
  }
  // Строки различаются только регистром: сравниваем как есть, чтобы порядок
  // оставался устойчивым.
  return a.compareTo(b);
}

/// Нижний регистр одного символа.
///
/// Латиница, кириллица и латиница-1 разобраны сдвигом — это те буквы, что
/// встречаются в именах файлов постоянно. Всё остальное уходит в `toLowerCase`
/// по одному символу: путь редкий, и выделение строки там не жалко.
int _toLower(int unit) {
  if (unit >= 0x41 && unit <= 0x5A) {
    return unit + 0x20; // A–Z
  }
  if (unit < 0x80) {
    return unit;
  }
  if (unit >= 0x410 && unit <= 0x42F) {
    return unit + 0x20; // А–Я
  }
  if (unit == 0x401) {
    return 0x451; // Ё
  }
  if (unit >= 0xC0 && unit <= 0xDE && unit != 0xD7) {
    return unit + 0x20; // À–Þ, кроме знака умножения
  }
  final lower = String.fromCharCode(unit).toLowerCase();
  return lower.isEmpty ? unit : lower.codeUnitAt(0);
}

/// Числа сравниваются по значению, ведущие нули не важны; при равенстве
/// короче — раньше, поэтому `file01` и `file1` не считаются одинаковыми.
///
/// Границами, а не подстроками: вырезать куски ради сравнения значило бы
/// выделять по две строки на каждое число в каждом сравнении.
int _compareNumbers(String a, int startA, int endA, String b, int startB, int endB) {
  var i = startA;
  var j = startB;

  // Ведущие нули ничего не значат — кроме случая, когда всё число из нулей.
  while (i < endA - 1 && a.codeUnitAt(i) == _zeroCode) {
    i++;
  }
  while (j < endB - 1 && b.codeUnitAt(j) == _zeroCode) {
    j++;
  }

  final lengthA = endA - i;
  final lengthB = endB - j;
  if (lengthA != lengthB) {
    return lengthA < lengthB ? -1 : 1;
  }

  while (i < endA) {
    final charA = a.codeUnitAt(i);
    final charB = b.codeUnitAt(j);
    if (charA != charB) {
      return charA < charB ? -1 : 1;
    }
    i++;
    j++;
  }

  // Значения равны: короче исходная запись — раньше.
  return (endA - startA).compareTo(endB - startB);
}

const int _zeroCode = 0x30;

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
