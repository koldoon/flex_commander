import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';

/// Помеченные объекты панели — реализация [PanelSelection].
///
/// Вынесена из панели отдельным объектом, чтобы строка списка подписывалась
/// только на пометку, а не на всё состояние панели: иначе перемещение курсора
/// перерисовывало бы всю таблицу. Наружу отдаётся интерфейсом, но сама
/// реализация ещё и [Listenable] — на это подписывается таблица.
class SelectionController extends ChangeNotifier implements PanelSelection {
  /// Порядок пометки сохраняется — он же становится порядком обработки
  /// в файловых операциях.
  final Set<FsNode> _nodes = <FsNode>{};

  @override
  List<FsNode> get nodes => List.unmodifiable(_nodes);

  @override
  int get length => _nodes.length;

  @override
  bool get isEmpty => _nodes.isEmpty;

  @override
  bool get isNotEmpty => _nodes.isNotEmpty;

  @override
  bool contains(FsNode node) => _nodes.contains(node);

  /// Суммарный размер помеченных объектов.
  ///
  /// В сумму входит всё, у чего размер известен, — в том числе каталог, размер
  /// которого уже посчитан (см. [FsNode.unknownSize]). Значение живое: узлы
  /// меняются по ходу обхода, и об этом уведомляет **панель**, а не пометка, —
  /// подписки на одну пометку для слежения за суммой недостаточно.
  @override
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
  @override
  void add(FsNode node) {
    if (node is ParentDirNode || !_nodes.add(node)) {
      return;
    }
    notifyListeners();
  }

  @override
  void remove(FsNode node) {
    if (_nodes.remove(node)) {
      notifyListeners();
    }
  }

  @override
  void toggle(FsNode node) {
    if (contains(node)) {
      remove(node);
    } else {
      add(node);
    }
  }

  @override
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

  @override
  void clear() {
    if (_nodes.isEmpty) {
      return;
    }
    _nodes.clear();
    notifyListeners();
  }

  /// Имена помеченных объектов. После перечитывания каталога узлы — новые
  /// экземпляры, поэтому пометка переносится именно по именам.
  @override
  Set<String> get names => {for (final node in _nodes) node.name};
}
