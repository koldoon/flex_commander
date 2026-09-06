import 'package:flutter/foundation.dart';

import 'package:fc_core_api/fc_core_api.dart';

/// Помеченные объекты панели — реализация [PanelSelection].
///
/// Вынесена из панели отдельным объектом, чтобы строка списка подписывалась
/// только на пометку, а не на всё состояние панели: иначе перемещение курсора
/// перерисовывало бы всю таблицу. Наружу отдаётся интерфейсом, но сама
/// реализация ещё и [Listenable] — на это подписывается таблица.
///
/// **Ключ объекта — его путь.** Узлы приходят разными экземплярами: каталог
/// перечитали, дерево спросило имена соседней ветви, операция разобрала путь
/// заново. Опознавать их самими объектами значит однажды сложить в пометку один
/// и тот же файл дважды — предохранитель стоит здесь, у самой пометки
/// (`docs/spec/panel-view-tree.md`, §7).
class SelectionController extends ChangeNotifier implements PanelSelection {
  /// Путь → узел. Порядок пометки сохраняется — он же становится порядком
  /// обработки в файловых операциях, а `Map` в Dart помнит порядок вставки.
  final Map<String, FsNode> _nodes = <String, FsNode>{};

  @override
  List<FsNode> get nodes => List.unmodifiable(_nodes.values);

  @override
  int get length => _nodes.length;

  @override
  bool get isEmpty => _nodes.isEmpty;

  @override
  bool get isNotEmpty => _nodes.isNotEmpty;

  /// Помечен ли **этот объект** — путём, а не экземпляром: узел мог приехать
  /// новым после перечитывания каталога.
  @override
  bool contains(FsNode node) => _nodes.containsKey(node.pathString);

  /// Суммарный размер помеченных объектов.
  ///
  /// В сумму входит всё, у чего размер известен, — в том числе каталог, размер
  /// которого уже посчитан (см. [FsNode.unknownSize]). Значение живое: узлы
  /// меняются по ходу обхода, и об этом уведомляет **панель**, а не пометка, —
  /// подписки на одну пометку для слежения за суммой недостаточно.
  @override
  int get totalSize {
    var total = 0;
    for (final node in _nodes.values) {
      if (node.size > 0) {
        total += node.size;
      }
    }
    return total;
  }

  /// Псевдоузел «..» не помечается никогда — поведение референса.
  ///
  /// Уже помеченный объект второй пометки не получает, и **прежний экземпляр
  /// остаётся**: за ним может идти обход размера, и подмена узла на полпути
  /// стоила бы посчитанного.
  @override
  void add(FsNode node) {
    if (node is ParentDirNode || _nodes.containsKey(node.pathString)) {
      return;
    }
    _nodes[node.pathString] = node;
    notifyListeners();
  }

  @override
  void remove(FsNode node) {
    if (_nodes.remove(node.pathString) != null) {
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
      if (node is ParentDirNode || _nodes.containsKey(node.pathString)) {
        continue;
      }
      _nodes[node.pathString] = node;
      added = true;
    }
    if (added) {
      notifyListeners();
    }
  }

  /// Заменить пометку целиком, уведомив один раз.
  ///
  /// Порядок — тот, в котором пришли узлы: он же порядок обработки в файловых
  /// операциях.
  @override
  void replaceWith(Iterable<FsNode> nodes) {
    final replacement = <String, FsNode>{};
    for (final node in nodes) {
      if (node is! ParentDirNode) {
        replacement[node.pathString] = node;
      }
    }
    if (_same(replacement)) {
      // Ничего не изменилось — и молчим: лишнее уведомление пересобирает
      // очередь обхода размеров и уносит стейт за границу впустую.
      return;
    }
    _nodes
      ..clear()
      ..addAll(replacement);
    notifyListeners();
  }

  /// Тот же ли это набор — и в том же ли порядке.
  bool _same(Map<String, FsNode> other) {
    if (other.length != _nodes.length) {
      return false;
    }
    final mine = _nodes.keys.iterator;
    final theirs = other.keys.iterator;
    while (mine.moveNext() && theirs.moveNext()) {
      if (mine.current != theirs.current || !identical(_nodes[mine.current], other[theirs.current])) {
        return false;
      }
    }
    return true;
  }

  @override
  void clear() {
    if (_nodes.isEmpty) {
      return;
    }
    _nodes.clear();
    notifyListeners();
  }

  /// Имена помеченных объектов — тем, кому нужно имя, а не объект.
  @override
  Set<String> get names => {for (final node in _nodes.values) node.name};

  /// Пути помеченных объектов, в порядке пометки: это и есть пометка, как её
  /// видит та сторона границы.
  @override
  Set<String> get paths => _nodes.keys.toSet();
}
