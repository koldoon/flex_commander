import 'package:fc_api/fc_api.dart';

import 'search_query.dart';

/// Обход дерева в поисках имён.
///
/// **Обычная работа поверх провайдера** (`listChildren`), а не поход по диску:
/// поэтому поиск сразу работает и в архиве, и по `ssh` — там, где стоит панель.
///
/// Найденное отдаётся **по ходу** ([onFound]), а не в конце: на большом дереве
/// первые попадания видны сразу, и обычно этого довольно. Итог работы — тот же
/// список целиком, для тех, кому нужен только он.
class SearchRun {
  /// Работа, которую остаётся запустить: `start` — и она пойдёт.
  static Operation<SearchQuery, List<FsNode>> from(DirectoryNode where, {required void Function(FsNode) onFound}) {
    return TaskOperation<SearchQuery, List<FsNode>>((op, query) async {
      final mask = FileMask.parse(query.mask);
      final found = <FsNode>[];
      if (mask.isEmpty) {
        // Пустая маска не совпадает ни с чем — обходить дерево незачем.
        return found;
      }

      final queue = <DirectoryNode>[where];
      while (queue.isNotEmpty) {
        // Прерывание проверяется на каждом каталоге, а не на каждом файле:
        // между каталогами и есть настоящее ожидание — чтение с диска или из
        // сети.
        await op.checkpoint();

        final dir = queue.removeAt(0);
        op.report(message: dir.pathString, indeterminate: true, itemsTransferred: found.length);

        final List<FsNode> children;
        try {
          children = await dir.provider.listChildren(dir);
        } on Object {
          // Каталог, в который не пустили, поиск не прекращает: непрочитанный
          // `/root` посреди дерева — обычное дело, а не повод бросить работу.
          continue;
        }

        for (final node in children) {
          if (!query.hidden && node.name.startsWith('.')) {
            continue;
          }
          if (mask.matches(node.name)) {
            found.add(node);
            onFound(node);
          }
          // Каталог может и сам подойти под маску, и содержать подходящее:
          // одно другому не мешает.
          if (query.recursive && node is DirectoryNode) {
            queue.add(node);
          }
        }
      }

      return found;
    });
  }
}
