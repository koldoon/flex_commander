import 'package:flutter/foundation.dart';

import 'fs_node.dart';

/// Помеченные объекты панели.
///
/// Живёт на стороне ядра, потому что говорит об узлах: пометка — это состояние
/// сеанса, а не экрана. Наружу от неё едут имена и сводка, и то и другое —
/// частью `PanelState` (`docs/spec/client-server.md`, §4.5).
///
/// [Listenable]: строка панели и её содержимое перерисовываются по изменению
/// пометки, поэтому подписка описана здесь, а не добирается приведением
/// к реализации.
abstract interface class PanelSelection implements Listenable {
  bool contains(FsNode node);

  /// Псевдоузел «..» не помечается никогда.
  void add(FsNode node);

  void remove(FsNode node);

  void toggle(FsNode node);

  void addAll(Iterable<FsNode> nodes);

  void clear();

  /// Помеченные объекты в порядке пометки — он же порядок обработки
  /// в файловых операциях.
  List<FsNode> get nodes;

  int get length;

  bool get isEmpty;

  bool get isNotEmpty;

  /// Суммарный размер помеченных объектов; объекты с неизвестным размером
  /// (каталоги) в сумму не входят.
  int get totalSize;

  /// Имена помеченных объектов: после перечитывания каталога узлы — новые
  /// экземпляры, и пометка переносится именно по именам.
  Set<String> get names;
}
