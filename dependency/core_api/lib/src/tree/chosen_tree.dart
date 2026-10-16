import 'package:fc_api/fc_api.dart';

import 'entry_value.dart';
import 'fs_node.dart';

/// Строки сжатого дерева из выбранных узлов: откуда каждый.
///
/// Так окно удаления показывает то, что уйдёт мимо корзины
/// (`docs/spec/trash-unavailable.md`, §4а): выбранное бывает из разных ветвей,
/// и плоский список не говорит, из каких. Корень — общий каталог всех [nodes],
/// между ним и узлами — их **настоящие** каталоги, раскрытые все; сами узлы не
/// раскрыты — их содержимого здесь не читали. Склеивает цепочки общий обход
/// [treeRows] — тот же, что у панели.
///
/// У корня в голове цепочки — каталог, в котором он лежит: корни не
/// склеиваются, и голова у них свободна, а ответ на «где это всё» нужен
/// именно здесь. Нет общего каталога (узлы разных источников) — корней
/// несколько.
List<FileEntry> chosenTreeRows(List<FsNode> nodes) {
  if (nodes.isEmpty) {
    return const [];
  }

  final chains = [for (final node in nodes) _directoriesAbove(node)];
  var common = chains.first;
  for (final chain in chains.skip(1)) {
    var same = 0;
    while (same < common.length && same < chain.length && common[same].pathString == chain[same].pathString) {
      same++;
    }
    common = common.sublist(0, same);
  }

  // Корни — с последнего общего каталога; нет общего — с верха каждой цепочки.
  final from = common.isEmpty ? 0 : common.length - 1;
  final roots = <String, _Branch>{};
  for (var i = 0; i < nodes.length; i++) {
    final chain = chains[i];
    _Branch? branch;
    for (var depth = from; depth < chain.length; depth++) {
      final dir = chain[depth];
      final level = branch == null ? roots : branch.kids;
      branch = level.putIfAbsent(dir.pathString, () => _Branch(dir, open: true));
    }
    (branch == null ? roots : branch.kids)[nodes[i].pathString] = _Branch(nodes[i], open: false);
  }

  return [
    for (final row in treeRows<_Branch>(
      roots.values.toList(),
      childrenOf: (branch, _) => branch.sorted,
      isOpen: (branch) => branch.open,
      isDirectory: (branch) => branch.node is DirectoryNode,
      compact: true,
    ))
      entryValueOf(row.branch.node).inTree(
        level: row.level,
        isOpen: row.open,
        hasBranches: row.branch.kids.values.any((kid) => kid.node is DirectoryNode),
        chainHead: row.level == 0 ? _whereOf(row.branch.node) : row.absorbed.map((it) => it.node.name).join('/'),
      ),
  ];
}

/// Каталоги над узлом, сверху вниз.
List<DirectoryNode> _directoriesAbove(FsNode node) {
  final path = node.path;
  return [
    for (final step in path.take(path.length - 1))
      if (step is DirectoryNode) step,
  ];
}

/// Где лежит корень — путём его каталога; у корня диска — пусто.
String _whereOf(FsNode node) {
  final where = node.parentDirectory?.displayPath ?? '';
  return where == '/' ? '' : where;
}

class _Branch {
  _Branch(this.node, {required this.open});

  final FsNode node;
  final bool open;

  /// Дети по пути — в том порядке, в каком легли; показ сортирует сам.
  final Map<String, _Branch> kids = {};

  /// Каталоги первыми, дальше по имени — как панель по умолчанию.
  List<_Branch> get sorted {
    final list = kids.values.toList();
    list.sort((a, b) {
      final aDir = a.node is DirectoryNode;
      final bDir = b.node is DirectoryNode;
      if (aDir != bDir) {
        return aDir ? -1 : 1;
      }
      return naturalCompare(a.node.name, b.node.name);
    });
    return list;
  }
}
