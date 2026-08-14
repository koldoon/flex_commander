import 'package:flutter/foundation.dart';

import '../model/tree/fs_node.dart';

/// Помеченные объекты панели.
///
/// Вынесена из панели отдельным объектом, чтобы строка списка подписывалась
/// только на пометку, а не на всё состояние панели: иначе перемещение курсора
/// перерисовывало бы всю таблицу.
class PanelSelection extends ChangeNotifier {
  /// Порядок пометки сохраняется — он же становится порядком обработки
  /// в файловых операциях.
  final Set<FsNode> _nodes = <FsNode>{};

  List<FsNode> get nodes => List.unmodifiable(_nodes);

  int get length => _nodes.length;

  bool get isEmpty => _nodes.isEmpty;

  bool get isNotEmpty => _nodes.isNotEmpty;

  bool contains(FsNode node) => _nodes.contains(node);

  /// Суммарный размер помеченных объектов; объекты с неизвестным размером
  /// (каталоги) в сумму не входят.
  int get totalSize {
    var total = 0;
    for (final node in _nodes) {
      if (node.size > 0) {
        total += node.size;
      }
    }
    return total;
  }

  /// Псевдоузел «..» не помечается никогда — поведение референса.
  void add(FsNode node) {
    if (node is ParentDirNode || !_nodes.add(node)) {
      return;
    }
    notifyListeners();
  }

  void remove(FsNode node) {
    if (_nodes.remove(node)) {
      notifyListeners();
    }
  }

  void toggle(FsNode node) {
    if (contains(node)) {
      remove(node);
    } else {
      add(node);
    }
  }

  void addAll(Iterable<FsNode> nodes) {
    var added = false;
    for (final node in nodes) {
      if (node is! ParentDirNode && _nodes.add(node)) {
        added = true;
      }
    }
    if (added) {
      notifyListeners();
    }
  }

  void clear() {
    if (_nodes.isEmpty) {
      return;
    }
    _nodes.clear();
    notifyListeners();
  }

  /// Имена помеченных объектов. После перечитывания каталога узлы — новые
  /// экземпляры, поэтому пометка переносится именно по именам.
  Set<String> get names => {for (final node in _nodes) node.name};
}
