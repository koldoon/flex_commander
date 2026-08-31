import '../async/async_operation.dart';
import '../util/file_name.dart';
import 'file_attributes.dart';
import 'file_type.dart';
import 'node_path.dart';
import 'tree_provider.dart';
import 'operation_params.dart';

/// Общий узел дерева.
///
/// Панель показывает не «список файлов», а каталог в дереве узлов: всё чтение и
/// изменение дерева спрятано за [TreeProvider], поэтому архив или удалённая
/// файловая система подключаются как ещё один провайдер, не затрагивая панель.
abstract class FsNode {
  /// Родительский узел. null только у корня провайдера.
  FsNode? get parent;

  /// Отображаемое имя, оно же ключ узла внутри родителя.
  String get name;

  /// Размер в байтах или [FsNode.unknownSize], если размер неизвестен.
  int get size;

  /// Полный путь строкой — через все провайдеры цепочки:
  /// `/home/archive.zip:zip:/inner/doc.txt`. Схема `fs` в начале не печатается,
  /// поэтому обычный путь выглядит обычно.
  ///
  /// Это адрес для машины: он сохраняется в настройках и разбирается обратно.
  /// Пользователю показывается [displayPath].
  String get pathString;

  /// Путь для показа пользователю: без схем провайдеров.
  ///
  /// `/home/archive.zip/inner/doc.txt` — внутрь архива входят как в каталог,
  /// и путь должен выглядеть так же.
  String get displayPath;

  /// Путь от корня дерева до этого узла включительно.
  List<FsNode> get path;

  /// Провайдер, которому принадлежит узел.
  TreeProvider get provider;

  /// Ближайший вверх по дереву каталог.
  DirectoryNode? get parentDirectory;

  /// Размер неизвестен: каталоги до подсчёта, битые ссылки, псевдоузел "..".
  ///
  /// Отличать «не посчитан» от «посчитан» важно: любое значение `>= 0` считается
  /// известным — в том числе ноль у пустого каталога и промежуточная сумма, пока
  /// обход идёт. Каталогам размер выставляет `PanelController`, когда их
  /// помечают.
  static const int unknownSize = -1;
}

/// Базовая реализация [FsNode]: имя, родитель, размер и обходы дерева вверх.
abstract class AbstractFsNode implements FsNode {
  AbstractFsNode({required this.provider, required this.name, this.parent, this.size = FsNode.unknownSize});

  @override
  final TreeProvider provider;

  @override
  final String name;

  @override
  final FsNode? parent;

  /// Размер меняется уже после создания узла: для каталогов его считает
  /// отдельная операция, для файлов он приходит вместе с `stat`.
  ///
  /// [FsNode.unknownSize] — «не посчитан»; см. там же про промежуточные суммы.
  @override
  int size;

  @override
  String get pathString => nodePathOf(this).toString();

  @override
  String get displayPath => nodePathOf(this).displayString;

  @override
  List<FsNode> get path {
    final result = <FsNode>[];
    FsNode? node = this;
    while (node != null) {
      result.insert(0, node);
      node = node.parent;
    }
    return result;
  }

  @override
  DirectoryNode? get parentDirectory {
    FsNode? node = parent;
    while (node != null && node is! DirectoryNode) {
      node = node.parent;
    }
    return node as DirectoryNode?;
  }

  @override
  String toString() => name;
}

/// Файл. Базовый класс и для каталогов, и для ссылок.
class FileNode extends AbstractFsNode {
  FileNode({
    required super.provider,
    required super.name,
    super.parent,
    super.size,
    this.fileType = FileType.regular,
    this.attributes = const FileAttributes.unknown(),
    this.modified,
    this.created,
    this.accessed,
    this.executable = false,
    this.broken = false,
  });

  FileType fileType;

  FileAttributes attributes;

  DateTime? modified;
  DateTime? created;
  DateTime? accessed;

  bool executable;

  /// Узел не удалось прочитать целиком: нет прав или он исчез во время чтения.
  bool broken;

  bool get hidden => name.startsWith('.');
}

/// Имя без пробелов по краям — и по краям основы.
///
/// Первое привычно, второе про то, как правят имя в поле: человек стирает
/// основу и оставляет пробел перед точкой. В списке такой пробел не виден
/// вовсе, а файл получается другой — `«отчёт .txt»` вместо `«отчёт.txt»`.
///
/// Где кончается основа, решает [ReferenceFileNaming] — **то же правило, что
/// рисует колонку расширения**. Иначе поле, список и колонка разошлись бы в
/// понимании того, что такое расширение: у `.gitignore` его нет, у
/// `архив.tar.gz` оно `gz`.
String trimmedFileName(String name) {
  final trimmed = name.trim();
  final (:base, :extension) = const ReferenceFileNaming().split(trimmed);
  if (extension.isEmpty) {
    return trimmed;
  }
  final trimmedBase = base.trimRight();
  // Основа, состоявшая из одних пробелов, оставила бы имя без имени: пусть
  // такое сохранится как есть и отвергнется проверкой имени.
  return trimmedBase.isEmpty ? trimmed : '$trimmedBase.$extension';
}

/// Каталог: может содержать другие узлы.
class DirectoryNode extends FileNode {
  DirectoryNode({
    required super.provider,
    required super.name,
    super.parent,
    super.size,
    super.attributes,
    super.modified,
    super.created,
    super.accessed,
    super.executable,
    super.broken,
  }) : super(fileType: FileType.directory);

  List<FsNode> _nodes = const [];

  /// Содержимое, загруженное последним чтением каталога.
  /// Порядок — как вернул провайдер; сортировка живёт в контроллере панели.
  List<FsNode> get nodes => _nodes;

  set nodes(List<FsNode> value) => _nodes = List.unmodifiable(value);

  /// Перечитать содержимое каталога: работа заведена и уже идёт.
  Operation<ListingParams, List<FsNode>> refresh() => provider.getDirectoryListing()..start(ListingParams(this));
}

/// Символическая ссылка.
class LinkNode extends FileNode {
  LinkNode({
    required super.provider,
    required super.name,
    required this.reference,
    this.targetType,
    super.parent,
    super.size,
    super.attributes,
    super.modified,
    super.created,
    super.accessed,
    super.executable,
    super.broken,
  }) : super(fileType: FileType.symbolicLink);

  /// Строка, на которую указывает ссылка, как её вернула файловая система:
  /// может быть относительной.
  final String reference;

  /// Тип цели, известный уже при чтении каталога: `stat` по ссылке всё равно
  /// идёт до цели, так что сортировка «каталоги вперёд» работает без
  /// отдельного разрешения ссылки. null у битой ссылки.
  final FileType? targetType;

  /// Цель ссылки; null, пока [resolve] не выполнен, и у битой ссылки.
  FsNode? target;

  /// Ссылка ведёт в каталог.
  bool get isDirectoryLink => target is DirectoryNode || targetType == FileType.directory;

  Operation<LinkNode, FsNode?> resolve() => provider.resolveLink()..start(this);
}

/// Верхний узел того же провайдера — корень поддерева, которое он показывает.
///
/// Выше может стоять чужое дерево: провайдер архива смонтирован над файлом
/// локальной ФС, и родитель его корня — этот самый файл.
FsNode providerRootOf(FsNode node) {
  var root = node;
  while (true) {
    final parent = root.parent;
    if (parent == null || !identical(parent.provider, node.provider)) {
      return root;
    }
    root = parent;
  }
}

/// Узлы пути, принадлежащие тому же провайдеру, что и [node], — от его корня.
///
/// Путь внутри провайдера складывается только из них: имена чужого дерева,
/// над которым он смонтирован, в него не входят.
List<FsNode> providerPathNodes(FsNode node) {
  final chain = node.path;
  return chain.sublist(chain.indexOf(providerRootOf(node)));
}

/// Полный путь узла через все провайдеры цепочки.
///
/// Собирается снизу вверх: каждый провайдер отвечает за свою часть, а над его
/// корнем стоит узел, к которому он примонтирован.
NodePath nodePathOf(FsNode node) {
  final parts = <NodePathPart>[];
  FsNode? current = node;

  while (current != null) {
    parts.insert(0, NodePathPart(current.provider.scheme, current.provider.pathOf(current)));
    current = providerRootOf(current).parent;
  }
  return NodePath(parts);
}

/// Узлы, из имён которых складывается **видимый** путь.
///
/// Цель ссылки не добавляет своё имя: путь должен показывать, как пользователь
/// сюда пришёл, а не куда ссылка ведёт. Для цепочки
/// `/ → etc(ссылка) → etc(каталог) → apache2` видимый путь — `/etc/apache2`,
/// а не `/private/etc/apache2`. Правило взято из `FileNodeUtil.getPath`
/// референса.
List<FsNode> visiblePathNodes(FsNode node) {
  final result = <FsNode>[];
  FsNode? previous;
  for (final current in providerPathNodes(node)) {
    if (previous is! LinkNode) {
      result.add(current);
    }
    previous = current;
  }
  return result;
}

/// Псевдоузел «..» — вход в родительский каталог.
///
/// В отличие от референса (там был один статический экземпляр на всё
/// приложение) создаётся отдельно для каждого каталога: так узлы остаются
/// различимыми, а пометка и восстановление курсора работают по идентичности.
class ParentDirNode extends AbstractFsNode {
  ParentDirNode(this.directory) : super(provider: directory.provider, name: '..', parent: directory);

  /// Каталог, в списке которого показан этот псевдоузел.
  final DirectoryNode directory;

  /// Каталог, в который ведёт «..». null, если [directory] — корень.
  DirectoryNode? get targetDirectory => directory.parentDirectory;

  @override
  String get pathString => targetDirectory?.pathString ?? directory.pathString;

  @override
  String get displayPath => targetDirectory?.displayPath ?? directory.displayPath;
}
