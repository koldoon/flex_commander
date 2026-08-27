import 'dart:io';

import 'package:fc_api/fc_api.dart';

import 'tar_index.dart';

/// Tar-архив как дерево.
///
/// Устроен обратно zip: у того оглавление лежит в конце и читается одним
/// прыжком, а содержимое сжато и потому распаковывается целиком. Здесь всё
/// наоборот — оглавления нет вовсе, и открытие стоит прохода по всему файлу,
/// зато содержимое лежит несжатым и подряд, и чтение записи стоит одного
/// прыжка.
class TarTreeProvider implements TreeProvider, FileContentProvider, ProviderLifecycle {
  TarTreeProvider._({
    required this.archivePath,
    required FsNode host,
    required TarIndex index,
    LocalCopySession? session,
  }) : _host = host,
       _index = index,
       _session = session;

  /// Схема для строк пути: `…/src.tar:tar:/lib/main.dart`.
  static const String schemeName = 'tar';

  /// Расширения, которые открываются этим провайдером.
  static const Set<String> extensions = {'tar'};

  /// Открывает архив: проходит по нему и строит указатель.
  ///
  /// Архив, лежащий не в локальной ФС — внутри `.gz`, внутри другого архива
  /// или на сервере, — сперва оказывается во временном файле: читать запись по
  /// смещению можно только там, где по файлу умеют прыгать. Владеет копией сам
  /// провайдер и убирает её в [dispose].
  static Future<TreeProvider> open(
    FsNode host, {
    required StagingArea staging,
    void Function(int bytes)? onBytes,
  }) async {
    final session = LocalCopySession(staging, prefix: 'flex_commander_tar');

    try {
      final path = await session.localPathOf(host, onBytes: onBytes);
      final index = await readTarIndex(path);
      return TarTreeProvider._(archivePath: path, host: host, index: index, session: session);
    } on Object {
      // Битый архив или отмена: копия не должна пережить неудачу.
      await session.purge();
      rethrow;
    }
  }

  /// Путь к файлу архива в локальной файловой системе.
  final String archivePath;

  /// Узел, над которым провайдер смонтирован: файл архива в чужом дереве.
  final FsNode _host;

  /// Оглавление, прочитанное один раз при открытии.
  final TarIndex _index;

  /// Временная копия архива; null — архив и так лежал в локальной ФС.
  final LocalCopySession? _session;

  bool _disposed = false;

  @override
  String get scheme => schemeName;

  /// Менять внутри нечего, настоящих путей нет — а вот прыгать по записи можно:
  /// она лежит несжатой, и `openRead` со смещением честно начинает с него.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(canSeek: true, maxConcurrency: 1);

  @override
  late final DirectoryNode rootDirectory = DirectoryNode(provider: this, name: '/', parent: _host);

  @override
  String get homePath => '/';

  /// Путь внутри архива — всегда с косой чертой, каким бы ни был разделитель
  /// снаружи: так он записан и в самом архиве.
  @override
  String pathOf(FsNode node) {
    final names = visiblePathNodes(node).skip(1).map((child) => child.name);
    return '/${names.join('/')}';
  }

  @override
  Operation<String, FsNode?> resolvePath() {
    return TaskOperation<String, FsNode?>((op, path) async {
      FsNode node = rootDirectory;
      TarEntry entry = _index.root;

      for (final name in _segments(path)) {
        final child = entry.children[name];
        if (child == null) {
          return null;
        }
        node = _nodeOf(child, node);
        entry = child;
      }
      return node;
    });
  }

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      final dir = params.dir;
      final entry = _entryOf(dir);
      if (entry == null || !entry.isDirectory) {
        throw FsError(dir.pathString, FsErrorKind.notFound);
      }

      final nodes = <FsNode>[
        // «..» из корня архива ведёт наружу — туда, где лежит сам архив.
        if (dir.parentDirectory != null) ParentDirNode(dir),
        for (final child in _childrenOf(entry, includeHidden: params.includeHidden)) _nodeOf(child, dir),
      ];

      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final entry = _entryOf(dir);
    if (entry == null) {
      throw FsError(dir.pathString, FsErrorKind.notFound);
    }
    return [for (final child in _childrenOf(entry, includeHidden: true)) _nodeOf(child, dir)];
  }

  /// Ссылка внутри архива ведёт в тот же архив, но разрешать её мы не беремся:
  /// цель бывает относительной, бывает наружу, а бывает и битой — как в zip,
  /// показываем саму ссылку.
  @override
  Operation<LinkNode, FsNode?> resolveLink() => CompletedOperation<LinkNode, FsNode?>(null);

  @override
  Future<void> countEntries(FsNode node, void Function(int bytes) onEntry) async {
    final entry = _entryOf(node);
    if (entry == null) {
      return;
    }
    _walk(entry, (child) => onEntry(child.isDirectory ? 0 : child.size));
  }

  /// Размер считается по оглавлению: обходить нечего, всё уже прочитано.
  @override
  Operation<List<FsNode>, int> calculateSize() {
    return TaskOperation<List<FsNode>, int>((op, nodes) async {
      var total = 0;
      for (final node in nodes) {
        op.checkCanceled();
        final entry = _entryOf(node);
        if (entry == null) {
          continue;
        }
        _walk(entry, (child) => total += child.isDirectory ? 0 : child.size);
        op.report(itemsTransferred: total, message: node.name);
      }
      return total;
    });
  }

  /// Содержимое записи — куском файла архива.
  ///
  /// Ни распаковки, ни памяти под запись: в tar она лежит как есть, и всё, что
  /// нужно, — прочитать нужный отрезок. Смещение работает по-настоящему,
  /// поэтому `canSeek: true`.
  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    if (_disposed) {
      throw FsError(archivePath, FsErrorKind.notSupported);
    }

    final entry = _entryOf(node);
    if (entry == null || entry.isDirectory) {
      throw FsError(node.pathString, FsErrorKind.notFound);
    }

    final start = entry.offset + offset.clamp(0, entry.size);
    return File(archivePath).openRead(start, entry.offset + entry.size);
  }

  /// Панель зовёт это, уходя из архива: временную копию пора убрать.
  @override
  Future<void> dispose() async {
    _disposed = true;
    await _session?.purge();
  }

  TarEntry? _entryOf(FsNode node) => _index.at(_segments(pathOf(node)));

  Iterable<TarEntry> _childrenOf(TarEntry entry, {required bool includeHidden}) {
    final children = entry.children.values.where((child) => includeHidden || !child.name.startsWith('.')).toList();
    // Порядок записей в архиве произвольный, а сортировкой заведует панель:
    // отдаём хотя бы устойчивый.
    children.sort((a, b) => a.name.compareTo(b.name));
    return children;
  }

  void _walk(TarEntry entry, void Function(TarEntry entry) visit) {
    visit(entry);
    for (final child in entry.children.values) {
      _walk(child, visit);
    }
  }

  /// Путь внутри архива разбирается своими силами: разделитель здесь всегда
  /// косая черта, каким бы ни был он в системе.
  List<String> _segments(String path) => path.split('/').where((name) => name.isNotEmpty && name != '.').toList();

  FsNode _nodeOf(TarEntry entry, FsNode parent) {
    final attributes = entry.mode == 0 ? const FileAttributes.unknown() : _attributesOf(entry);

    if (entry.isDirectory) {
      return DirectoryNode(
        provider: this,
        name: entry.name,
        parent: parent,
        attributes: attributes,
        modified: entry.modified,
      );
    }

    final link = entry.linkTarget;
    if (link != null) {
      // Ссылки — то, ради чего мир Unix и пользуется tar: они переносятся
      // ссылками, а не разыменовываются (`spec/link-transfer.md`).
      return LinkNode(
        provider: this,
        name: entry.name,
        parent: parent,
        reference: link,
        size: entry.size,
        attributes: attributes,
        modified: entry.modified,
      );
    }

    return FileNode(
      provider: this,
      name: entry.name,
      parent: parent,
      size: entry.size,
      attributes: attributes,
      modified: entry.modified,
      executable: attributes.isExecutable,
    );
  }

  FileAttributes _attributesOf(TarEntry entry) {
    final type =
        entry.isDirectory
            ? FileType.directory
            : entry.linkTarget != null
            ? FileType.symbolicLink
            : FileType.regular;
    return FileAttributes(mode: entry.mode, modeString: '${type.attributeChar}${_modeString(entry.mode)}');
  }

  /// «rwxr-xr-x» из режима доступа: `dart:io` умеет это только для своих
  /// объектов, а режим в архиве — обычное число.
  static String _modeString(int mode) {
    const flags = ['r', 'w', 'x'];
    final buffer = StringBuffer();
    for (var bit = 8; bit >= 0; bit--) {
      buffer.write(mode & (1 << bit) != 0 ? flags[2 - bit % 3] : '-');
    }
    return buffer.toString();
  }
}
