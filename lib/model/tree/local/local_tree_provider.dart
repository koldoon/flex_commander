import 'dart:io';

import 'package:path/path.dart' as p;

import '../../async/async_operation.dart';
import '../file_attributes.dart';
import '../file_type.dart';
import '../fs_node.dart';
import '../node_path.dart';
import '../tree_provider.dart';
import 'local_listing.dart';

/// Провайдер дерева поверх локальной файловой системы.
///
/// В референсной реализации то же самое делалось запуском `ls` и `stat`, потому
/// что в AIR не было нормального API файловой системы. Здесь есть `dart:io`,
/// а внешние утилиты понадобятся позже — для копирования с прогрессом.
class LocalTreeProvider implements TreeProvider, TreeEditor {
  LocalTreeProvider({String? homePath, this.readInIsolate = true}) : homePath = homePath ?? _detectHomePath();

  /// Домашний каталог пользователя — сюда открываются панели, если сохранённый
  /// путь недоступен.
  @override
  final String homePath;

  /// Чтение каталога в отдельном изоляте. Отключается в тестах, где каталоги
  /// маленькие, а лишний изолят только замедляет прогон.
  final bool readInIsolate;

  @override
  String get scheme => NodePath.defaultScheme;

  late final DirectoryNode _root = DirectoryNode(provider: this, name: p.rootPrefix(homePath));

  @override
  DirectoryNode get rootDirectory => _root;

  /// Видимый путь: ссылки в нём остаются ссылками.
  ///
  /// Пользователь, зашедший в `/etc`, должен видеть `/etc`, а по «..» попадать
  /// в `/`, а не в `/private`, куда ведёт настоящая цель.
  @override
  String pathOf(FsNode node) => _join(visiblePathNodes(node).map((n) => n.name).toList());

  /// Настоящий путь в файловой системе: все ссылки развёрнуты.
  ///
  /// Именно он используется для чтения каталогов и файловых операций.
  /// Алгоритм повторяет `FileNodeUtil.getAbsoluteFileSystemPath` референса.
  String physicalPathOf(FsNode node) {
    var segments = <String>[];
    FsNode? previous;

    for (final current in node.path) {
      if (previous is LinkNode && segments.isNotEmpty) {
        // Имя, добавленное целью предыдущей ссылки, заменяется тем, куда эта
        // ссылка на самом деле ведёт.
        segments.removeLast();
      }

      if (current is LinkNode) {
        final reference = current.reference;
        if (reference.isEmpty) {
          segments.add(current.name);
        } else if (p.isAbsolute(reference)) {
          segments = p.split(reference);
        } else {
          segments.addAll(p.split(reference));
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
      return p.rootPrefix(homePath);
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
      op.report(OperationProgress(message: 'Reading ${pathOf(dir)}…'));

      final entries =
          readInIsolate
              ? await readDirectory(path, includeHidden: includeHidden)
              : await readDirectorySync(path, includeHidden: includeHidden);

      op.checkCanceled();

      final nodes = <FsNode>[
        if (dir.parentDirectory != null) ParentDirNode(dir),
        for (final entry in entries) nodeFromEntry(entry, dir),
      ];

      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  AsyncOperation<FsNode?> resolvePath(String path) {
    return TaskOperation<FsNode?>((op) async {
      final normalized = p.normalize(p.absolute(path));
      final segments = p.split(normalized);

      // Корень строится один раз и живёт вместе с провайдером, поэтому все
      // цепочки узлов от разных вызовов сходятся в одном и том же корне.
      DirectoryNode parent = _root;
      if (segments.length == 1) {
        return _root;
      }

      for (var i = 1; i < segments.length; i++) {
        op.checkCanceled();

        final name = segments[i];
        // Путь ребёнка считается от настоящего пути родителя: если выше по
        // цепочке была ссылка, читать нужно там, куда она ведёт.
        final childPath = p.join(physicalPathOf(parent), name);
        final entry = await _describePath(childPath, name);
        if (entry == null) {
          return null;
        }

        final node = nodeFromEntry(entry, parent);
        final isLast = i == segments.length - 1;
        if (isLast) {
          return node;
        }
        if (node is! DirectoryNode) {
          // Промежуточный элемент пути не каталог: дальше идти некуда.
          // Ссылка на каталог допустима — разворачиваем её и продолжаем.
          // Цель становится дочерним узлом ссылки, поэтому видимый путь
          // по-прежнему идёт через неё.
          if (node is LinkNode && node.isDirectoryLink) {
            final target = await _resolveTarget(node);
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

  @override
  AsyncOperation<FsNode?> resolveLink(LinkNode link) {
    return TaskOperation<FsNode?>((op) async {
      final target = await _resolveTarget(link);
      op.checkCanceled();
      return target;
    });
  }

  /// Создаёт каталог внутри [parent].
  ///
  /// Каталог создаётся по настоящему пути (ссылки развёрнуты), но узел
  /// возвращается дочерним для [parent] — панель показывает его там, где
  /// пользователь находится.
  @override
  AsyncOperation<DirectoryNode> makeDirectory(DirectoryNode parent, String name) {
    return TaskOperation<DirectoryNode>((op) async {
      final path = p.join(physicalPathOf(parent), name);
      if (name.isEmpty || name == '.' || name == '..' || name.contains(p.separator) || name.contains('/')) {
        throw FsError(name, FsErrorKind.invalidName);
      }

      if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound) {
        throw FsError(path, FsErrorKind.alreadyExists);
      }

      try {
        await Directory(path).create();
      } on FileSystemException catch (error) {
        throw fsErrorFrom(path, error);
      }
      op.checkCanceled();

      final entry = await _describePath(path, name);
      if (entry == null) {
        throw FsError(path, FsErrorKind.io);
      }
      return nodeFromEntry(entry, parent) as DirectoryNode;
    });
  }

  // Копирование, перемещение и удаление появятся следующими шагами этого
  // этапа; команды за ними пока не закреплены.
  @override
  TransferOperation copy() => throw UnimplementedError('Копирование ещё не реализовано');

  @override
  TransferOperation move() => throw UnimplementedError('Перемещение ещё не реализовано');

  @override
  AsyncOperation<void> remove(List<FsNode> nodes, {bool toTrash = true}) =>
      throw UnimplementedError('Удаление ещё не реализовано');

  /// Строит узел дерева по сырой записи каталога.
  ///
  /// Родителем может быть и ссылка: её разрешённая цель становится дочерним
  /// узлом самой ссылки.
  FsNode nodeFromEntry(RawEntry entry, FsNode parent) {
    final attributes =
        entry.modeString.isEmpty
            ? const FileAttributes.unknown()
            : FileAttributes(mode: entry.mode, modeString: entry.modeString);

    return switch (entry.fileType) {
      FileType.symbolicLink => LinkNode(
        provider: this,
        name: entry.name,
        parent: parent,
        reference: entry.linkTarget ?? '',
        targetType: entry.linkTargetType,
        size: entry.size,
        attributes: attributes,
        modified: entry.modified,
        created: entry.changed,
        accessed: entry.accessed,
        executable: attributes.isExecutable,
        broken: entry.broken,
      ),
      FileType.directory => DirectoryNode(
        provider: this,
        name: entry.name,
        parent: parent,
        attributes: attributes,
        modified: entry.modified,
        created: entry.changed,
        accessed: entry.accessed,
        broken: entry.broken,
      ),
      _ => FileNode(
        provider: this,
        name: entry.name,
        parent: parent,
        size: entry.size,
        fileType: entry.fileType,
        attributes: attributes,
        modified: entry.modified,
        created: entry.changed,
        accessed: entry.accessed,
        executable: attributes.isExecutable,
        broken: entry.broken,
      ),
    };
  }

  /// Разрешает ссылку: цель становится **дочерним узлом самой ссылки**.
  ///
  /// Так дерево помнит, как пользователь сюда попал: видимый путь идёт через
  /// ссылку, а переход наверх возвращает в каталог, где эта ссылка лежит,
  /// а не туда, где физически находится её цель. Цепочки ссылок разворачиваются
  /// до первого «настоящего» узла, повторы отслеживаются — иначе закольцованная
  /// ссылка увела бы в бесконечность.
  Future<FsNode?> _resolveTarget(LinkNode link) async {
    final visited = <String>{};
    LinkNode current = link;

    while (true) {
      if (current.reference.isEmpty) {
        return null;
      }

      final path = physicalPathOf(current);
      if (!visited.add(path)) {
        // Ссылка ведёт сама на себя по кругу.
        return null;
      }

      final entry = await _describePath(path, p.basename(path));
      if (entry == null) {
        return null;
      }

      final target = nodeFromEntry(entry, current);
      current.target = target;

      if (target is LinkNode) {
        current = target;
        continue;
      }
      return target;
    }
  }

  Future<RawEntry?> _describePath(String path, String name) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return null;
    }

    String? linkTarget;
    FileType? linkTargetType;
    if (type == FileSystemEntityType.link) {
      try {
        linkTarget = await Link(path).target();
      } on FileSystemException {
        linkTarget = '';
      }
    }

    FileStat stat;
    try {
      stat = await FileStat.stat(path);
    } on FileSystemException {
      return RawEntry(name: name, fileType: FileType.fromEntityType(type), linkTarget: linkTarget, broken: true);
    }

    if (stat.type == FileSystemEntityType.notFound) {
      return RawEntry(name: name, fileType: FileType.fromEntityType(type), linkTarget: linkTarget, broken: true);
    }

    final statType = FileType.fromEntityType(stat.type);
    if (type == FileSystemEntityType.link) {
      linkTargetType = statType;
    }
    final fileType = type == FileSystemEntityType.link ? FileType.symbolicLink : statType;

    return RawEntry(
      name: name,
      fileType: fileType,
      size: statType == FileType.directory ? FsNode.unknownSize : stat.size,
      modified: stat.modified,
      accessed: stat.accessed,
      changed: stat.changed,
      mode: stat.mode,
      modeString: '${fileType.attributeChar}${stat.modeString()}',
      linkTarget: linkTarget,
      linkTargetType: linkTargetType,
    );
  }

  static String _detectHomePath() {
    final env = Platform.environment;
    final home = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
    if (home != null && home.isNotEmpty) {
      return home;
    }
    return Directory.current.path;
  }
}
