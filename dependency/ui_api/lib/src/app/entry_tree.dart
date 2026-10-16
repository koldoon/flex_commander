import 'package:fc_api/fc_api.dart';

/// Строки сжатого дерева из готовых значений — без узлов и без ядра.
///
/// Так окно показывает выбранное из разных ветвей: удаление мимо корзины
/// называет, **откуда** уходит каждый объект (`docs/spec/trash-unavailable.md`,
/// §4а). Корень — общий каталог всех [entries], между ним и объектами —
/// достроенные каталоги, раскрытые все. Склеивает цепочки общий обход
/// [treeRows] — тот же, что у панели.
///
/// Сами объекты — строки как есть: каталог среди них не раскрыт, его
/// содержимого здесь не читали.
List<FileEntry> entryTreeRows(List<FileEntry> entries) {
  if (entries.isEmpty) {
    return const [];
  }

  final places = [for (final entry in entries) _segmentsOf(_directoryOf(entry))];
  var common = places.first;
  for (final place in places.skip(1)) {
    var same = 0;
    while (same < common.length && same < place.length && common[same] == place[same]) {
      same++;
    }
    common = common.sublist(0, same);
  }

  final rootPath = _join(common);
  final root = _Branch(
    FileEntry(
      // Корень зовётся путём целиком: он и есть ответ на «где это всё лежит».
      name: rootPath,
      kind: EntryKind.directory,
      path: rootPath,
      directoryPath: _join(common.isEmpty ? common : common.sublist(0, common.length - 1)),
    ),
    open: true,
  );

  for (var i = 0; i < entries.length; i++) {
    var branch = root;
    final place = places[i];
    for (var depth = common.length; depth < place.length; depth++) {
      final name = place[depth];
      branch = branch.kids.putIfAbsent(
        name,
        () => _Branch(
          FileEntry(
            name: name,
            kind: EntryKind.directory,
            path: _join(place.sublist(0, depth + 1)),
            directoryPath: _join(place.sublist(0, depth)),
          ),
          open: true,
        ),
      );
    }
    branch.kids[entries[i].name] = _Branch(entries[i], open: false);
  }

  return [
    for (final row in treeRows<_Branch>(
      [root],
      childrenOf: (branch, _) => branch.sorted,
      isOpen: (branch) => branch.open,
      isDirectory: (branch) => branch.entry.kind == EntryKind.directory,
      compact: true,
    ))
      row.branch.entry.inTree(
        level: row.level,
        isOpen: row.open,
        hasBranches: row.branch.kids.values.any((kid) => kid.entry.kind == EntryKind.directory),
        chainHead: row.absorbed.map((it) => it.entry.name).join('/'),
      ),
  ];
}

/// Каталог объекта: тот, что назвал источник, а нет — из пути.
String _directoryOf(FileEntry entry) {
  if (entry.directoryPath.isNotEmpty) {
    return entry.directoryPath;
  }
  final slash = entry.path.lastIndexOf('/');
  return slash <= 0 ? '/' : entry.path.substring(0, slash);
}

/// Звенья пути: `/a/b` — `['', 'a', 'b']`; адрес со схемой режется так же, и
/// общая часть у двух адресов одного сервера остаётся общей.
List<String> _segmentsOf(String path) {
  final trimmed = path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  return trimmed == '/' ? const [''] : trimmed.split('/');
}

String _join(List<String> segments) {
  final joined = segments.join('/');
  return joined.isEmpty ? '/' : joined;
}

class _Branch {
  _Branch(this.entry, {required this.open});

  final FileEntry entry;
  final bool open;

  /// Дети по имени — в том порядке, в каком легли; показ сортирует сам.
  final Map<String, _Branch> kids = {};

  /// Каталоги первыми, дальше по имени — как панель по умолчанию.
  List<_Branch> get sorted {
    final list = kids.values.toList();
    list.sort((a, b) {
      final aDir = a.entry.kind == EntryKind.directory;
      final bDir = b.entry.kind == EntryKind.directory;
      if (aDir != bDir) {
        return aDir ? -1 : 1;
      }
      return naturalCompare(a.entry.name, b.entry.name);
    });
    return list;
  }
}
