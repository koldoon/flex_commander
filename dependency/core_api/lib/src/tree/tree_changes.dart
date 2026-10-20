import 'fs_node.dart';

/// Что стало с узлами — фактами, для тех, кто держит чужие узлы у себя.
///
/// Находки поиска держат настоящие узлы своих провайдеров, пока их не
/// закроют. Переименованный узел для них — уже не тот: старого имени на месте
/// нет, и сверка его выбросила бы (`docs/spec/file-search.md`, §13.6). Движок
/// знает и прежний узел, и новый — он и сообщает.
///
/// Одна на ядро: пишет движок, слушает всякий, кто держит узлы, а не только
/// поиск. Синхронно: слушатель обновляется до того, как работа сообщит о конце
/// и панель перечитается.
class TreeChanges {
  final List<void Function(FsNode from, FsNode to)> _renamed = [];

  /// Слушать переименования; ответ — как перестать.
  void Function() onRenamed(void Function(FsNode from, FsNode to) listener) {
    _renamed.add(listener);
    return () => _renamed.remove(listener);
  }

  /// Узел [from] переименован и теперь — [to].
  void renamed(FsNode from, FsNode to) {
    for (final listener in List.of(_renamed)) {
      listener(from, to);
    }
  }
}
