import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Найденное — как содержимое панели.
///
/// Живёт в ядре, а не у окна поиска, и это не переезд ради переезда: узлы в нём
/// **настоящие** и принадлежат своим провайдерам, а провайдеры бывают только по
/// эту сторону границы (`docs/spec/client-server.md`, §5.1.6).
///
/// Источник над найденным, и найденное в нём — **дерево**, а не плоский список:
/// между корнем и находкой стоят каталоги, в которых она лежала. Видно, где что
/// нашлось, а не только сколько всего (`docs/spec/file-search.md`, §4).
///
/// Каталоги эти **виртуальные**: они принадлежат этому источнику, и содержимое
/// у них — только найденное. Настоящий каталог отдал бы всё, что в нём есть, и
/// находки утонули бы среди соседей. А вот сами находки — настоящие узлы своих
/// провайдеров: копирование, удаление, `F3` и `F4` работают над ними без единой
/// правки, команда спрашивает узел, а не панель. Найденный каталог и
/// раскрывается настоящим: ветвь читает провайдер самого узла
/// (`docs/spec/panel-node-list.md`, §3).
///
/// Из этого же следует, чего источник **не** делает. Обход поддерева и подсчёт
/// размеров — вопросы к тому, кому узел принадлежит; здесь на них отвечать
/// нечем и незачем.
class SearchResultsProvider
    implements TreeProvider, PanelColumns, PanelPreferredView, PanelNaturalOrder, RealPathSource {
  SearchResultsProvider({required String title, required List<FsNode> found, DirectoryNode? parent}) : _under = parent {
    _root = DirectoryNode(provider: this, name: title, parent: parent);
    _build(found);
  }

  /// Каталог, в котором искали: от него и считается вложенность находок.
  ///
  /// Он же родитель корня — поэтому `..` из находок возвращает туда, где панель
  /// стояла, и никакого «запомненного места» для этого не нужно.
  final DirectoryNode? _under;

  late final DirectoryNode _root;

  /// Виртуальные каталоги по их пути — по ним же собираются ветви.
  final Map<String, DirectoryNode> _branches = {};

  /// Настоящий каталог за каждой ветвью.
  ///
  /// Ветвь показывает найденное, но значит — тот каталог, из которого это
  /// найдено: туда её открывают в соседней панели (`Alt-O`), оттуда её
  /// показывает система. Снаружи это видно как [FileEntry.realPath].
  final Map<DirectoryNode, DirectoryNode> _mirrors = {};

  /// Настоящий путь узла: у ветви — каталог, который она показывает.
  ///
  /// У корня своего нет: он не каталог, а список, сложившийся по маске.
  @override
  String realPathOf(FsNode node) {
    if (!identical(node.provider, this)) {
      return node.provider.capabilities.realFileSystem ? node.pathString : '';
    }
    final real = _mirrors[node];
    if (real == null) {
      return '';
    }
    return real.provider.capabilities.realFileSystem ? real.pathString : '';
  }

  /// Что нашлось — в том порядке, в каком находилось.
  final List<FsNode> _found = [];

  List<FsNode> get found => List.unmodifiable(_found);

  /// Найденное показывается деревом: плоским списком структуры не видно.
  ///
  /// Имя вида — то, под которым его объявил модуль панелей (`TreeView.viewId`).
  /// Ядро видов не знает и знать не должно: для него это строка, как и та, что
  /// лежит в настройках панели.
  @override
  String get preferredView => 'tree';

  /// Пути виртуальных ветвей: их дерево раскрывает сразу.
  ///
  /// Иначе находка, лежавшая на три каталога вглубь, пряталась бы за тремя
  /// нажатиями — а показать найденное и есть всё, зачем этот источник заведён.
  @override
  Iterable<String> get openBranches => [_root.pathString, ..._branches.keys];

  /// Добавить найденное: список растёт, пока идёт обход.
  ///
  /// Панель показывает находки **по ходу** поиска, а не только итог: обход над
  /// большим деревом идёт минутами, и ждать его, глядя в готовый список,
  /// незачем (`docs/spec/file-search.md`, §4).
  void add(List<FsNode> found) {
    if (found.isEmpty) {
      return;
    }
    _build(found);
  }

  /// Раскладывает находки по ветвям: каталоги между каталогом поиска и
  /// находкой становятся виртуальными.
  void _build(List<FsNode> found) {
    // Прибавляется к тому, что уже разложено: список растёт по ходу обхода, и
    // пересобирать его целиком на каждую пачку было бы работой впустую.
    final children = <DirectoryNode, List<FsNode>>{};
    for (final node in found) {
      _found.add(node);
      children.putIfAbsent(_branchFor(node, children), () => []).add(node);
    }
    for (final entry in children.entries) {
      entry.key.nodes = [...entry.key.nodes, ...entry.value];
    }
  }

  /// Виртуальный каталог, в который ложится находка; корень — если она лежала
  /// прямо в каталоге поиска.
  DirectoryNode _branchFor(FsNode node, Map<DirectoryNode, List<FsNode>> children) {
    var branch = _root;
    for (final real in _chainOf(node)) {
      final path = '${branch.pathString}/${real.name}';
      final made = _branches[path];
      if (made != null) {
        branch = made;
        continue;
      }
      final virtual = DirectoryNode(provider: this, name: real.name, parent: branch, modified: real.modified);
      _branches[path] = virtual;
      _mirrors[virtual] = real;
      children.putIfAbsent(branch, () => []).add(virtual);
      branch = virtual;
    }
    return branch;
  }

  /// Настоящие каталоги между каталогом поиска и находкой, сверху вниз.
  ///
  /// Не дошли до каталога поиска — значит находка не из-под него (так бывает у
  /// ссылок, уводящих в сторону): она ложится в корень, а не тянет за собой
  /// цепочку до самого диска.
  List<DirectoryNode> _chainOf(FsNode node) {
    final under = _under?.pathString;
    final chain = <DirectoryNode>[];
    var dir = node.parentDirectory;
    while (dir != null && dir.pathString != under) {
      chain.insert(0, dir);
      dir = dir.parentDirectory;
    }
    return dir == null ? const [] : chain;
  }

  @override
  String get scheme => SourceInfo.foundScheme;

  /// Колонки списка находок: к обычным добавлена колонка пути.
  ///
  /// Дерево показывает, откуда каждая находка, ветвями, но в таблице этого
  /// нет — а имена в находках повторяются. Настройку панели это не трогает:
  /// раскладку просит источник, и уходит она вместе с ним.
  ///
  /// Сравнения у находок обычные: колонка пути сравнивает **настоящий**
  /// каталог найденного объекта, а его знает и ядро. Своё сравнение
  /// понадобится тому источнику, чья колонка ядру незнакома.
  @override
  NodeComparator? comparatorOf(FsColumn column) => null;

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

  /// Путь узла внутри этого источника — имена ветвей от корня.
  ///
  /// Свой, а не настоящий: у виртуальной ветви настоящего пути нет, а строки,
  /// пометка и раскрытое живут путями и обязаны различаться. Настоящий узел
  /// отвечает своим — его спрашивают не здесь, но `pathOf` зовут и напрямую.
  @override
  String pathOf(FsNode node) {
    if (!identical(node.provider, this)) {
      return node.pathString;
    }
    final names = <String>[];
    FsNode? current = node;
    while (current != null && identical(current.provider, this)) {
      names.insert(0, current.name);
      current = current.parent;
    }
    return '/${names.join('/')}';
  }

  /// Список ветви — с «..», как у всякого источника: из находок возвращаются
  /// им же, а не только `Esc` (`docs/spec/file-search.md`, §4).
  ///
  /// В [listChildren] его нет: там содержимое ветви, а дерево псевдострок не
  /// показывает.
  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() => TaskOperation<ListingParams, List<FsNode>>(
    (op, params) async => [
      if (params.dir.parentDirectory != null) ParentDirNode(params.dir),
      ...await listChildren(params.dir),
    ],
  );

  /// Содержимое ветви — только найденное. Чужой каталог свой список отдаёт сам.
  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async =>
      identical(dir.provider, this) ? dir.nodes : dir.provider.listChildren(dir);

  /// Разбор пути — по своим же ветвям; чего нет, тем и отвечать нечем.
  @override
  Operation<String, FsNode?> resolvePath() =>
      TaskOperation<String, FsNode?>((op, path) async => path == _root.pathString ? _root : _branches[path] ?? _root);

  /// Ссылку разрешает тот, кому она принадлежит.
  @override
  Operation<LinkNode, FsNode?> resolveLink() =>
      TaskOperation<LinkNode, FsNode?>((op, link) async => link.provider.resolveLink().run(link));
}
