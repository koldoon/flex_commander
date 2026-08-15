import '../tree/fs_node.dart';

/// Помеченные объекты панели.
///
/// Интерфейс, а не класс: команды работают с пометкой через него и ничего не
/// знают о том, как она устроена внутри (аналог `IPanelSelection` референса).
abstract interface class PanelSelection {
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
