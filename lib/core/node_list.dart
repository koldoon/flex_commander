import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'listing_cache.dart';

/// Откуда панель берёт строки.
///
/// Панель показывает **список узлов**, а не содержимое каталога: строки
/// собираются из набора корней цепочкой «источник → мапперы → сортировка →
/// фильтры» (`docs/spec/panel-node-list.md`). Здесь первое звено — то, чем
/// строки набираются; сортировка и пометка остаются делом сеанса.
///
/// Сегодня набор один — [DirectoryNodeList], каталог с одним корнем. Дерево и
/// находки станут другими наборами, и панель об этом не узнает: она спрашивает
/// строки, а не читает каталог.
abstract interface class NodeList {
  /// Корни, из которых собираются строки. У каталога он один; у дерева и
  /// избранного их бывает несколько.
  List<FsNode> get roots;

  /// Каталог, куда пойдёт операция, пока курсор не сказал иного.
  ///
  /// Временное звено: сейчас на нём держатся аренда, оболочка и плашка, и
  /// расстаться с ним получится не раньше, чем строки начнёт собирать маппер
  /// (шаг 5 эпика).
  DirectoryNode get directory;

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
  Operation<void, List<FsNode>> read({required bool includeHidden});
}

/// Строки одного каталога — тот самый случай, которым панель жила до сих пор.
class DirectoryNodeList implements NodeList {
  const DirectoryNodeList(this.directory);

  @override
  final DirectoryNode directory;

  @override
  List<FsNode> get roots => [directory];

  @override
  List<FsNode>? shown(ListingCache? cache, {required bool includeHidden}) =>
      cache?.take(directory, includeHidden: includeHidden);

  @override
  void remember(ListingCache? cache, List<FsNode> rows, {required bool includeHidden}) =>
      cache?.put(directory, rows, includeHidden: includeHidden);

  @override
  Operation<void, List<FsNode>> read({required bool includeHidden}) {
    // Отмена доходит до чтения провайдера сама: `delegate` ведёт вложенную
    // работу и прерывает её вместе с этой.
    return TaskOperation<void, List<FsNode>>(
      (op, _) =>
          op.delegate(directory.provider.getDirectoryListing(), ListingParams(directory, includeHidden: includeHidden)),
    );
  }
}
