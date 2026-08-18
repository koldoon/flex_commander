import 'package:flex_commander/model/async/async_operation.dart';
import 'package:flex_commander/model/tree/file_attributes.dart';
import 'package:flex_commander/model/tree/file_type.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/node_path.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:path/path.dart' as p;

/// Описание объекта в фейковом дереве.
class FakeEntry {
  FakeEntry.directory(this.path) : type = FileType.directory, size = FsNode.unknownSize, linkTarget = null;

  FakeEntry.file(this.path, {this.size = 0, this.modified}) : type = FileType.regular, linkTarget = null;

  FakeEntry.link(this.path, this.linkTarget) : type = FileType.symbolicLink, size = FsNode.unknownSize;

  final String path;
  final FileType type;
  final int size;
  final String? linkTarget;
  DateTime? modified;

  String get name => p.basename(path);
}

/// Провайдер дерева в памяти: те же контракты, что у настоящего, но без диска.
///
/// Узлы создаются заново на каждое чтение — как и в [LocalTreeProvider],
/// поэтому тесты контроллеров честно проверяют перенос курсора и пометки
/// по именам, а не по совпадению экземпляров.
///
/// Реализует [NodeEditor] — примитивы, и только их: копирование и удаление
/// выполняет тот же `TreeTransferEngine`, что и в приложении, поэтому фейку
/// больше не нужно повторять его механику (и незаметно расходиться с ней).
class InMemoryTreeProvider implements TreeProvider, NodeEditor {
  InMemoryTreeProvider([List<FakeEntry> entries = const []]) {
    for (final entry in entries) {
      add(entry);
    }
  }

  final Map<String, FakeEntry> _entries = {};

  /// Каталоги, чтение которых заканчивается ошибкой.
  final Map<String, FsError> denied = {};

  /// Умеет ли провайдер переименовывать и есть ли у него корзина: так тест
  /// заставляет движок пойти запасной стратегией.
  bool renames = true;
  bool hasTrash = true;

  /// Что и какой стратегией сделал движок — по путям объектов.
  final List<String> renamed = [];
  final List<String> copied = [];
  final List<String> deleted = [];
  final List<String> trashed = [];

  void add(FakeEntry entry) {
    _entries[p.normalize(entry.path)] = entry;
  }

  /// Убрать объект из фикстуры (имитация удаления снаружи приложения).
  void removeEntry(String path) => _entries.remove(p.normalize(path));

  @override
  String get scheme => NodePath.defaultScheme;

  late final DirectoryNode _root = DirectoryNode(provider: this, name: '/');

  @override
  DirectoryNode get rootDirectory => _root;

  @override
  String get homePath => '/';

  /// Видимый путь: цель ссылки своё имя не добавляет.
  @override
  String pathOf(FsNode node) => _join(visiblePathNodes(node).map((n) => n.name).toList());

  /// Настоящий путь: ссылки развёрнуты.
  String physicalPathOf(FsNode node) {
    var segments = <String>[];
    FsNode? previous;

    for (final current in node.path) {
      if (previous is LinkNode && segments.isNotEmpty) {
        segments.removeLast();
      }
      if (current is LinkNode && current.reference.isNotEmpty) {
        if (p.isAbsolute(current.reference)) {
          segments = p.split(current.reference);
        } else {
          segments.addAll(p.split(current.reference));
        }
      } else {
        segments.add(current.name);
      }
      previous = current;
    }
    return _join(segments);
  }

  String _join(List<String> segments) {
    if (segments.isEmpty) {
      return '/';
    }
    if (segments.length == 1) {
      return segments.first;
    }
    return p.normalize(segments.reduce((value, name) => p.join(value, name)));
  }

  @override
  AsyncOperation<List<FsNode>> getDirectoryListing(DirectoryNode dir, {bool includeHidden = false}) {
    return TaskOperation<List<FsNode>>((op) async {
      final path = physicalPathOf(dir);
      final error = denied[path];
      if (error != null) {
        throw error;
      }

      final children =
          _entries.values
              .where((e) => p.dirname(e.path) == path && e.path != path)
              .where((e) => includeHidden || !e.name.startsWith('.'))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));

      op.checkCanceled();

      final nodes = <FsNode>[
        if (dir.parentDirectory != null) ParentDirNode(dir),
        for (final entry in children) _nodeFrom(entry, dir),
      ];
      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  AsyncOperation<FsNode?> resolvePath(String path) {
    return TaskOperation<FsNode?>((op) async {
      final normalized = p.normalize(path);
      final segments = p.split(normalized);
      DirectoryNode parent = _root;
      if (segments.length == 1) {
        return _root;
      }

      for (var i = 1; i < segments.length; i++) {
        final childPath = p.join(physicalPathOf(parent), name(segments, i));
        final entry = _entries[p.normalize(childPath)];
        if (entry == null) {
          return null;
        }
        final node = _nodeFrom(entry, parent);
        if (i == segments.length - 1) {
          return node;
        }
        if (node is! DirectoryNode) {
          if (node is LinkNode) {
            final target = await resolveLink(node).result;
            if (target is DirectoryNode) {
              parent = target;
              continue;
            }
          }
          return null;
        }
        parent = node;
      }
      return parent;
    });
  }

  /// Цель ссылки становится дочерним узлом самой ссылки — как в настоящем
  /// провайдере, иначе тесты навигации проверяли бы не то поведение.
  @override
  AsyncOperation<FsNode?> resolveLink(LinkNode link) {
    return TaskOperation<FsNode?>((op) async {
      final entry = _entries[p.normalize(physicalPathOf(link))];
      if (entry == null) {
        return null;
      }
      final target = _nodeFrom(entry, link);
      link.target = target;
      return target;
    });
  }

  String name(List<String> segments, int index) => segments[index];

  /// Подсчёт размера в памяти: те же промежуточные суммы, что и на диске, —
  /// иначе тесты проверяли бы не то поведение.
  @override
  AsyncOperation<int> calculateSize(List<FsNode> nodes) {
    return TaskOperation<int>((op) async {
      var total = 0;

      for (final node in nodes) {
        op.checkCanceled();
        final path = p.normalize(physicalPathOf(node));

        for (final entry in _entries.values.toList()) {
          final entryPath = p.normalize(entry.path);
          if (entryPath != path && !entryPath.startsWith('$path/')) {
            continue;
          }
          if (entry.size > 0) {
            total += entry.size;
          }
          // Пауза между объектами: подсчёт идёт фоном и в памяти тоже.
          // Микрозадача, а не таймер: тестам не приходится крутить часы.
          await Future<void>.microtask(() {});
          op.checkCanceled();
          op.report(OperationProgress(processed: total, message: node.name));
        }
      }

      return total;
    });
  }

  @override
  Future<DirectoryNode> createDirectory(DirectoryNode parent, String name) async {
    final path = p.join(physicalPathOf(parent), name);
    if (name.isEmpty || name.contains('/')) {
      throw FsError(name, FsErrorKind.invalidName);
    }
    if (_entries.containsKey(p.normalize(path))) {
      throw FsError(path, FsErrorKind.alreadyExists);
    }

    add(FakeEntry.directory(path));
    return _nodeFrom(_entries[p.normalize(path)]!, parent) as DirectoryNode;
  }

  /// Содержимое каталога для движка: со скрытыми, без «..» и без записи
  /// в [DirectoryNode.nodes] — обход не должен трогать то, что видит панель.
  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final path = physicalPathOf(dir);
    final children =
        _entries.values.where((e) => p.dirname(e.path) == path && e.path != path).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return [for (final entry in children) _nodeFrom(entry, dir)];
  }

  @override
  Future<FsNode?> lookup(DirectoryNode parent, String name) async {
    final entry = _entries[p.normalize(p.join(physicalPathOf(parent), name))];
    return entry == null ? null : _nodeFrom(entry, parent);
  }

  /// Копия объекта: файлы и ссылки, каталог создаёт и обходит движок.
  @override
  Future<bool> copyEntry(FsNode node, DirectoryNode destination, String name) async {
    final source = p.normalize(physicalPathOf(node));
    final entry = _entries[source];
    if (entry == null) {
      throw FsError(source, FsErrorKind.notFound);
    }
    if (entry.type == FileType.directory) {
      return false;
    }

    add(_cloneAt(entry, p.normalize(p.join(physicalPathOf(destination), name))));
    copied.add(source);
    return true;
  }

  /// Переименование. В памяти оно возможно всегда: «другого диска» здесь нет.
  @override
  Future<bool> renameEntry(FsNode node, DirectoryNode destination, String name) async {
    final source = p.normalize(physicalPathOf(node));
    if (!_entries.containsKey(source)) {
      throw FsError(source, FsErrorKind.notFound);
    }
    if (!renames) {
      // Способ проверить запасной путь движка: копирование с удалением.
      return false;
    }

    final target = p.normalize(p.join(physicalPathOf(destination), name));
    for (final key in _subtreeOf(source)) {
      final entry = _entries.remove(key)!;
      add(_cloneAt(entry, p.normalize(p.join(target, p.relative(key, from: source)))));
    }
    renamed.add(source);
    return true;
  }

  @override
  Future<void> deleteEntry(FsNode node) async {
    final path = p.normalize(physicalPathOf(node));
    if (!_entries.containsKey(path)) {
      throw FsError(path, FsErrorKind.notFound);
    }
    _entries.remove(path);
    deleted.add(path);
  }

  @override
  Future<bool> deleteTree(FsNode node) async {
    final path = p.normalize(physicalPathOf(node));
    if (!_entries.containsKey(path)) {
      throw FsError(path, FsErrorKind.notFound);
    }
    _removeTree(path);
    return true;
  }

  /// Корзины у фейка нет: движок удалит объект обходом.
  @override
  Future<bool> trashEntry(FsNode node) async {
    if (!hasTrash) {
      return false;
    }
    final path = p.normalize(physicalPathOf(node));
    if (!_entries.containsKey(path)) {
      throw FsError(path, FsErrorKind.notFound);
    }
    _removeTree(path);
    trashed.add(path);
    return true;
  }

  /// Подсчёт объектов задания. В памяти он мгновенный, но проходит теми же
  /// шагами, что и на диске: счётчики в окне команды должны заполняться так же.
  @override
  Future<void> countEntries(FsNode node, void Function() onEntry) async {
    for (final _ in _subtreeOf(p.normalize(physicalPathOf(node)))) {
      onEntry();
    }
  }

  @override
  bool isSameEntity(FsNode node, DirectoryNode destination) =>
      p.equals(physicalPathOf(node), p.join(physicalPathOf(destination), node.name));

  @override
  bool isInsideSource(FsNode node, DirectoryNode destination) =>
      p.isWithin(p.normalize(physicalPathOf(node)), p.normalize(p.join(physicalPathOf(destination), node.name)));

  void _removeTree(String path) {
    _entries.removeWhere((key, _) => key == path || key.startsWith('$path/'));
  }

  FakeEntry _cloneAt(FakeEntry entry, String path) => switch (entry.type) {
    FileType.directory => FakeEntry.directory(path),
    FileType.symbolicLink => FakeEntry.link(path, entry.linkTarget ?? ''),
    _ => FakeEntry.file(path, size: entry.size, modified: entry.modified),
  };

  /// Пути объекта и всего, что под ним.
  List<String> _subtreeOf(String path) => [
    for (final key in _entries.keys)
      if (key == path || key.startsWith('$path/')) key,
  ];

  FsNode _nodeFrom(FakeEntry entry, FsNode parent) {
    const attributes = FileAttributes(mode: 0x1FF, modeString: 'rwxrwxrwx');
    return switch (entry.type) {
      FileType.directory => DirectoryNode(
        provider: this,
        name: entry.name,
        parent: parent,
        modified: entry.modified,
        attributes: attributes,
      ),
      FileType.symbolicLink => LinkNode(
        provider: this,
        name: entry.name,
        parent: parent,
        reference: entry.linkTarget ?? '',
        targetType: _typeOfTarget(entry),
        modified: entry.modified,
        attributes: attributes,
      ),
      _ => FileNode(
        provider: this,
        name: entry.name,
        parent: parent,
        size: entry.size,
        modified: entry.modified,
        attributes: attributes,
      ),
    };
  }

  FileType? _typeOfTarget(FakeEntry entry) {
    final target = entry.linkTarget;
    if (target == null) {
      return null;
    }
    return _entries[p.normalize(target)]?.type;
  }
}
