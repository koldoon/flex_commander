/// Строка дерева, какой её выдаёт [treeRows]: ветвь, глубина и то, что она
/// поглотила цепочкой.
class TreeRow<B> {
  const TreeRow(this.branch, {required this.level, required this.open, this.absorbed = const []});

  /// Ветвь, которая стоит строкой, — в цепочке самая глубокая.
  final B branch;

  /// Глубина начала цепочки: дети стоят на ступень глубже.
  final int level;

  /// Раскрыта ли строка — тогда за ней идут её дети.
  final bool open;

  /// Поглощённые каталоги, начало цепочки первым; пусто — строка своя.
  final List<B> absorbed;
}

/// Разворачивает дерево в строки — и склеивает цепочки, если [compact].
///
/// Один обход на всех, кто показывает дерево: ядро разворачивает им панель, а
/// окно — свой снимок (`docs/spec/trash-unavailable.md`, §4а). Правило склейки
/// (`docs/spec/panel-view-compact-tree.md`, §2) живёт здесь и только здесь —
/// иначе два списка однажды склеились бы по-разному. Складывает строки каждый
/// по-своему.
///
/// - [childrenOf] — **показанные** дети ветви на глубине `level`, уже
///   отобранные и отсортированные; null — ветвь не прочитана.
/// - [isOpen] — раскрыта ли ветвь.
/// - [isDirectory] — каталог ли: только каталог тянет цепочку дальше, ссылка и
///   архив её обрывают.
///
/// Корни идут как даны и не склеиваются: их выбрали нарочно.
Iterable<TreeRow<B>> treeRows<B>(
  List<B> roots, {
  required List<B>? Function(B branch, int level) childrenOf,
  required bool Function(B branch) isOpen,
  required bool Function(B branch) isDirectory,
  bool compact = false,
}) {
  Iterable<TreeRow<B>> walk(List<B> shown, int level) sync* {
    for (final top in shown) {
      var branch = top;
      // Дети строки, если их уже отобрали, проходя цепочку: второй раз
      // отбирать незачем.
      List<B>? kids;
      final absorbed = <B>[];

      // Цепочка: раскрытый прочитанный каталог с единственным показанным
      // подкаталогом поглощается им.
      if (compact && level > 0) {
        while (isDirectory(branch) && isOpen(branch)) {
          final inside = childrenOf(branch, level + 1);
          if (inside == null) {
            break;
          }
          if (inside.length != 1 || !isDirectory(inside.single)) {
            kids = inside;
            break;
          }
          absorbed.add(branch);
          branch = inside.single;
        }
      }

      final open = isOpen(branch);
      yield TreeRow(branch, level: level, open: open, absorbed: absorbed);
      if (open) {
        yield* walk(kids ?? childrenOf(branch, level + 1) ?? const [], level + 1);
      }
    }
  }

  return walk(roots, 0);
}
