import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'listing_cache.dart';

/// Как раскладывать строки: сравнение и показывать ли скрытое.
///
/// Два звена цепочки — сортировка и фильтры — приходят вместе, потому что
/// вместе и применяются: у каталога к плоскому списку, у дерева внутри каждой
/// ветви (`docs/spec/panel-node-list.md`, §3).
class NodeListOrder {
  const NodeListOrder({required this.compare, required this.includeHidden});

  /// Порядок источника: строки идут так, как он их отдал.
  ///
  /// Нужен растущим спискам — находкам: они прибывают по ходу обхода, и всякая
  /// сортировка вставляла бы новое в середину, перекладывая уже прочитанное на
  /// экране (`docs/spec/file-search.md`, §4).
  const NodeListOrder.asGiven({required this.includeHidden}) : compare = null;

  /// Правило панели со сравнением колонки — тем, которое отдал источник, или
  /// встроенным.
  factory NodeListOrder.of(
    SortSpec sort, {
    required bool includeHidden,
    NodeComparator? column,
    FileNaming naming = const ReferenceFileNaming(),
  }) => NodeListOrder(compare: comparatorFor(sort, naming: naming, column: column), includeHidden: includeHidden);

  /// Чем сравнивать; null — не переставлять вовсе.
  final NodeComparator? compare;
  final bool includeHidden;
}

/// Откуда панель берёт строки.
///
/// Панель показывает **список узлов**, а не содержимое каталога: строки
/// собираются из набора корней цепочкой «источник → мапперы → сортировка →
/// фильтры» (`docs/spec/panel-node-list.md`). Здесь эта цепочка и живёт;
/// пометка, курсор и размеры остаются делом сеанса.
///
/// Наборов два: [DirectoryNodeList] — каталог с одним корнем, и `TreeNodeList`
/// — дерево, развёрнутое построчно. Панель об этом не знает: она спрашивает
/// строки, а не читает каталог.
abstract interface class NodeList {
  /// Корни, из которых собираются строки. У каталога он один; у дерева и
  /// избранного их бывает несколько.
  List<FsNode> get roots;

  /// Каталог, к которому набор привязан: его аренда и его оболочка.
  DirectoryNode get directory;

  /// Куда пойдёт операция, когда курсор стоит на этой строке.
  ///
  /// У списка каталога это сам каталог, у дерева — каталог строки под
  /// курсором: там видно много каталогов сразу, и другого осмысленного ответа
  /// нет. null — «не меняется»: так отвечает корень дерева, который ни в чём не
  /// лежит (`docs/spec/panel-view-tree.md`, §3).
  String? currentPathFor(FsNode? cursor);

  /// Строки, которые панель уже видела; null — таких нет.
  ///
  /// Подсказка, а не ответ: чтение пойдёт следом в любом случае
  /// (`docs/spec/listing-cache.md`, §3).
  List<FsNode>? shown(ListingCache? cache, {required bool includeHidden});

  /// Запомнить собранное для следующего показа.
  void remember(ListingCache? cache, List<FsNode> rows, {required bool includeHidden});

  /// Работа, которая соберёт строки заново.
  ///
  /// Работой, а не голым `Future`: панель её отменяет, когда человек уже
  /// попросил другое.
  Operation<void, List<FsNode>> read({required NodeListOrder order});

  /// Разложить уже собранные строки заново — когда сменилось правило, а
  /// содержимое нет.
  ///
  /// У каталога это обычная сортировка списка, у дерева — сортировка внутри
  /// ветвей: плоская перемешала бы ветви с их содержимым.
  List<FsNode> reorder(List<FsNode> rows, NodeListOrder order);
}

/// Строки одного каталога — тот самый случай, которым панель жила до сих пор.
class DirectoryNodeList implements NodeList {
  const DirectoryNodeList(this.directory);

  @override
  final DirectoryNode directory;

  @override
  List<FsNode> get roots => [directory];

  @override
  String? currentPathFor(FsNode? cursor) => directory.displayPath;

  @override
  List<FsNode>? shown(ListingCache? cache, {required bool includeHidden}) =>
      cache?.take(directory, includeHidden: includeHidden);

  @override
  void remember(ListingCache? cache, List<FsNode> rows, {required bool includeHidden}) =>
      cache?.put(directory, rows, includeHidden: includeHidden);

  @override
  Operation<void, List<FsNode>> read({required NodeListOrder order}) {
    // Отмена доходит до чтения провайдера сама: `delegate` ведёт вложенную
    // работу и прерывает её вместе с этой.
    return TaskOperation<void, List<FsNode>>(
      (op, _) async => reorder(
        await op.delegate(
          directory.provider.getDirectoryListing(),
          ListingParams(directory, includeHidden: order.includeHidden),
        ),
        order,
      ),
    );
  }

  @override
  List<FsNode> reorder(List<FsNode> rows, NodeListOrder order) {
    final compare = order.compare;
    return compare == null ? rows : (rows.toList()..sort(compare));
  }
}
