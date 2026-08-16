import 'package:flex_commander/model/async/async_operation.dart';
import 'package:flex_commander/model/async/operation_request.dart';
import 'package:flex_commander/model/async/transfer_progress.dart';
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
  AsyncOperation<void> copy(List<FsNode> nodes, DirectoryNode destination) =>
      _transfer(nodes, destination, move: false);

  @override
  AsyncOperation<void> move(List<FsNode> nodes, DirectoryNode destination) => _transfer(nodes, destination, move: true);

  /// Копирование и перенос в памяти: те же вопросы и тот же порядок, что и в
  /// настоящем провайдере, — иначе тесты команд проверяли бы не то поведение.
  AsyncOperation<void> _transfer(List<FsNode> nodes, DirectoryNode destination, {required bool move}) {
    return TaskOperation<void>((op) async {
      final targetDir = p.normalize(physicalPathOf(destination));
      final progress = TransferProgress(op, move ? 'Moving' : 'Copying');
      var overwriteAll = false;
      var skipAll = false;

      final sources = [for (final node in nodes) p.normalize(physicalPathOf(node))];
      // В памяти подсчёт мгновенный, но проходит теми же шагами, что и на диске:
      // счётчики в окне команды должны заполняться так же.
      for (var i = 0; i < sources.length; i++) {
        var counted = 0;
        for (final key in _entries.keys) {
          if (key == sources[i] || key.startsWith('${sources[i]}/')) {
            counted++;
            progress.countOne();
          }
        }
        progress.sourceCounted(i, counted);
      }
      progress.countingFinished();

      for (var i = 0; i < nodes.length; i++) {
        op.checkCanceled();

        final node = nodes[i];
        final source = sources[i];
        final target = p.normalize(p.join(targetDir, node.name));
        progress.startSource(node.name);

        if (!_entries.containsKey(source)) {
          progress.sourceDoneWholly(i);
          if (skipAll) {
            continue;
          }
          final answer = await _askAboutFailure(op, FsError(source, FsErrorKind.notFound).message);
          if (answer == OperationOption.skipAll) {
            skipAll = true;
          }
          continue;
        }

        if (_entries.containsKey(target)) {
          if (skipAll) {
            progress.sourceDoneWholly(i);
            continue;
          }
          if (!overwriteAll) {
            final answer = await op.ask(
              OperationRequest(
                message: 'Already exists: $target',
                options: const [
                  OperationOption.overwrite,
                  OperationOption.overwriteAll,
                  OperationOption.skip,
                  OperationOption.skipAll,
                  OperationOption.cancel,
                ],
                defaultOption: OperationOption.skip,
              ),
            );
            if (answer == OperationOption.cancel) {
              throw const OperationCanceled();
            }
            if (answer == OperationOption.skipAll) {
              skipAll = true;
              progress.sourceDoneWholly(i);
              continue;
            }
            if (answer == OperationOption.skip) {
              progress.sourceDoneWholly(i);
              continue;
            }
            if (answer == OperationOption.overwriteAll) {
              overwriteAll = true;
            }
          }
          _removeTree(target);
        }

        _copyTree(source, target, progress);
        if (move) {
          _removeTree(source);
        }
      }

      progress.stop();
      progress.finish();
    });
  }

  Future<OperationOption> _askAboutFailure(TaskOperation<void> op, String message) {
    return op.ask(
      OperationRequest(
        message: message,
        options: const [OperationOption.skip, OperationOption.skipAll, OperationOption.cancel],
        defaultOption: OperationOption.skip,
      ),
    );
  }

  /// Копирует объект вместе со всем, что под ним.
  void _copyTree(String source, String target, TransferProgress progress) {
    for (final entry in _entries.values.toList()) {
      final path = p.normalize(entry.path);
      if (path != source && !path.startsWith('$source/')) {
        continue;
      }
      progress.advance(entry.name);
      add(_cloneAt(entry, p.normalize(p.join(target, p.relative(path, from: source)))));
    }
  }

  void _removeTree(String path) {
    _entries.removeWhere((key, _) => key == path || key.startsWith('$path/'));
  }

  FakeEntry _cloneAt(FakeEntry entry, String path) => switch (entry.type) {
    FileType.directory => FakeEntry.directory(path),
    FileType.symbolicLink => FakeEntry.link(path, entry.linkTarget ?? ''),
    _ => FakeEntry.file(path, size: entry.size, modified: entry.modified),
  };

  /// Удаление в памяти: повторяет поведение настоящего провайдера — пропущенный
  /// объект не прекращает работу, а вопрос задаётся тем же способом.
  @override
  AsyncOperation<void> remove(List<FsNode> nodes, {bool toTrash = true}) {
    return TaskOperation<void>((op) async {
      var skipAll = false;

      for (final node in nodes) {
        op.checkCanceled();
        final path = p.normalize(physicalPathOf(node));

        if (_entries.containsKey(path)) {
          // Каталог удаляется вместе с содержимым.
          _entries.removeWhere((key, _) => key == path || key.startsWith('$path/'));
          continue;
        }

        if (skipAll) {
          continue;
        }
        final answer = await _askAboutFailure(op, FsError(path, FsErrorKind.notFound).message);
        if (answer == OperationOption.cancel) {
          throw const OperationCanceled();
        }
        if (answer == OperationOption.skipAll) {
          skipAll = true;
        }
      }
    });
  }

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
