import '../async/async_operation.dart';
import 'file_attributes.dart';
import 'file_type.dart';
import 'tree_provider.dart';

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

  /// Текст для строки состояния, когда узел под курсором.
  /// Полный путь строкой.
  String get pathString;

  /// Путь от корня дерева до этого узла включительно.
  List<FsNode> get path;

  /// Провайдер, которому принадлежит узел.
  TreeProvider get provider;

  /// Ближайший вверх по дереву каталог.
  DirectoryNode? get parentDirectory;

  /// Размер неизвестен: каталоги до подсчёта, битые ссылки, псевдоузел "..".
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
  @override
  int size;

  @override
  @override
  String get pathString => provider.pathOf(this);

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
  }) : _extension = _extensionOf(name);

  /// Расширение считается «настоящим», только если оно не длиннее 12 символов
  /// и не содержит пробелов: имя `.gitignore` расширения не имеет, а
  /// `archive.tar.gz` имеет расширение `gz`. Правило взято из референса.
  static final RegExp fileExtensionRe = RegExp(r'^([^\/*?|]+)\.([^\/*?|\s]{1,12})$');

  static String _extensionOf(String name) {
    final match = fileExtensionRe.firstMatch(name);
    return match?.group(2) ?? '';
  }

  final String _extension;

  /// Расширение без точки. Пустое, если его нет.
  String get extension => _extension;

  FileType fileType;

  FileAttributes attributes;

  DateTime? modified;
  DateTime? created;
  DateTime? accessed;

  bool executable;

  /// Узел не удалось прочитать целиком: нет прав или он исчез во время чтения.
  bool broken;

  /// Имя без расширения. Показывается в колонке «Имя», когда расширение
  /// вынесено в отдельную колонку.
  String get baseName => extension.isEmpty ? name : name.substring(0, name.length - extension.length - 1);

  bool get hidden => name.startsWith('.');
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

  /// У каталога расширения нет: `my.backup` — это не «файл .backup».
  @override
  String get extension => '';

  @override
  String get baseName => name;

  /// Перечитать содержимое каталога.
  AsyncOperation<List<FsNode>> refresh() => provider.getDirectoryListing(this);
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

  AsyncOperation<FsNode?> resolve() => provider.resolveLink(this);
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
  for (final current in node.path) {
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
}
