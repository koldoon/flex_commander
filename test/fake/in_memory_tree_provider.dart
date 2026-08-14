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
class InMemoryTreeProvider implements TreeProvider {
  InMemoryTreeProvider([List<FakeEntry> entries = const []]) {
    for (final entry in entries) {
      add(entry);
    }
  }

  final Map<String, FakeEntry> _entries = {};

  /// Каталоги, чтение которых заканчивается ошибкой.
  final Map<String, FsError> denied = {};

  void add(FakeEntry entry) {
    _entries[p.normalize(entry.path)] = entry;
  }

  void remove(String path) => _entries.remove(p.normalize(path));

  @override
  String get scheme => NodePath.defaultScheme;

  late final DirectoryNode _root = DirectoryNode(provider: this, name: '/');

  @override
  DirectoryNode get rootDirectory => _root;

  @override
  String pathOf(FsNode node) {
    final segments = node.path.map((n) => n.name).toList();
    if (segments.length == 1) {
      return segments.first;
    }
    return p.normalize(segments.reduce((value, name) => p.join(value, name)));
  }

  @override
  AsyncOperation<List<FsNode>> getDirectoryListing(DirectoryNode dir, {bool includeHidden = false}) {
    return TaskOperation<List<FsNode>>((op) async {
      final path = pathOf(dir);
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
        final childPath = p.joinAll(segments.sublist(0, i + 1));
        final entry = _entries[childPath];
        if (entry == null) {
          return null;
        }
        final node = _nodeFrom(entry, parent);
        if (i == segments.length - 1) {
          return node;
        }
        if (node is! DirectoryNode) {
          return null;
        }
        parent = node;
      }
      return parent;
    });
  }

  @override
  AsyncOperation<FsNode?> resolveLink(LinkNode link) {
    return TaskOperation<FsNode?>((op) async {
      final base = link.parentDirectory;
      final target =
          p.isAbsolute(link.reference) ? link.reference : p.join(base == null ? '/' : pathOf(base), link.reference);
      final node = await resolvePath(target).result;
      link.target = node;
      return node;
    });
  }

  FsNode _nodeFrom(FakeEntry entry, DirectoryNode parent) {
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
