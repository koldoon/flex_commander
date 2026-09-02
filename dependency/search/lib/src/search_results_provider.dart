import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Найденное — как содержимое панели.
///
/// Источник над **плоским списком**: каталогов в нём нет, вложенности нет,
/// корень один. Узлы в нём **настоящие** и принадлежат своим провайдерам —
/// поэтому копирование, удаление, `F3` и `F4` работают над ними без единой
/// правки: команда спрашивает узел, а не панель.
///
/// Из этого же следует, чего он **не** делает. Разбор пути, обход поддерева и
/// подсчёт размеров — вопросы к тому, кому узел принадлежит; здесь на них
/// отвечать нечем и незачем. Панель об этом не спотыкается: она просит список
/// каталога, а он готов заранее.
class SearchResultsProvider implements TreeProvider, PanelColumns {
  SearchResultsProvider({required String title, required List<FsNode> found, DirectoryNode? parent}) {
    _root = DirectoryNode(provider: this, name: title, parent: parent);
    _root.nodes = found;
  }

  late final DirectoryNode _root;

  /// Что нашлось — в том порядке, в каком находилось.
  List<FsNode> get found => _root.nodes;

  @override
  String get scheme => 'found';

  /// Колонки списка находок: к обычным добавлена колонка пути.
  ///
  /// Без неё список нечитаем: имена в нём повторяются, а различает строки
  /// только то, откуда каждая. Настройку панели это не трогает — раскладку
  /// просит источник, и уходит она вместе с ним.
  @override
  ColumnLayout get columns => ColumnLayout([
    for (final column in ColumnLayout.defaults.columns)
      column.id == FsColumn.path ? column.copyWith(visible: true) : column,
  ]);

  @override
  DirectoryNode get rootDirectory => _root;

  @override
  String get homePath => '/';

  /// Не настоящая файловая система: путей у этого списка нет, и обещать их
  /// нельзя. Оболочке здесь не работать, панель это учтёт сама.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  /// Путь узла — его собственный, из его источника.
  ///
  /// В плоском списке одни имена бесполезны: `main.dart` там будет десяток, и
  /// откуда каждый — единственное, что их различает.
  ///
  /// Сам список зовётся маской, по которой сложился: в шапке панели это
  /// читается как «`*.dart` под `/home`» — так же, как читается архив,
  /// открытый внутри каталога.
  @override
  String pathOf(FsNode node) => identical(node, _root) ? '/${_root.name}' : node.pathString;

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() =>
      TaskOperation<ListingParams, List<FsNode>>((op, params) async => _root.nodes);

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async => identical(dir, _root) ? _root.nodes : const [];

  /// Путей внутри списка находок не бывает: он один и он весь тут.
  @override
  Operation<String, FsNode?> resolvePath() => TaskOperation<String, FsNode?>((op, path) async => _root);

  /// Ссылку разрешает тот, кому она принадлежит.
  @override
  Operation<LinkNode, FsNode?> resolveLink() =>
      TaskOperation<LinkNode, FsNode?>((op, link) async => link.provider.resolveLink().run(link));

  @override
  Future<void> countEntries(FsNode node, void Function(int bytes) onEntry) => node.provider.countEntries(node, onEntry);

  @override
  Operation<List<FsNode>, int> calculateSize() => TaskOperation<List<FsNode>, int>((op, nodes) async {
    var total = 0;
    for (final node in nodes) {
      total += await node.provider.calculateSize().run([node]);
    }
    return total;
  });
}
