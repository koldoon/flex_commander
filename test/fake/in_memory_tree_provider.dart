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
class InMemoryTreeProvider implements TreeProvider, TreeEditor {
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

  @override
  AsyncOperation<DirectoryNode> makeDirectory(DirectoryNode parent, String name) {
    return TaskOperation<DirectoryNode>((op) async {
      final path = p.join(physicalPathOf(parent), name);
      if (name.isEmpty || name.contains('/')) {
        throw FsError(name, FsErrorKind.invalidName);
      }
      if (_entries.containsKey(p.normalize(path))) {
        throw FsError(path, FsErrorKind.alreadyExists);
      }

      add(FakeEntry.directory(path));
      return _nodeFrom(_entries[p.normalize(path)]!, parent) as DirectoryNode;
    });
  }

  @override
  TransferOperation copy() => throw UnimplementedError();

  @override
  TransferOperation move() => throw UnimplementedError();

  @override
  AsyncOperation<void> remove(List<FsNode> nodes, {bool toTrash = true}) => throw UnimplementedError();

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
