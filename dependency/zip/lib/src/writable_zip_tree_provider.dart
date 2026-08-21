part of 'zip_tree_provider.dart';

/// Архив, в который можно писать.
///
/// Zip — контейнер, а не файловая система: дописать в него запись «на месте»
/// нельзя, архив пересобирается целиком. Поэтому изменения копятся, а
/// пересборка случается один раз на всю работу — движок операций сообщает её
/// границы ([BatchedWrites]). Одиночное действие вроде `F7` границ не имеет и
/// пересобирает архив сразу.
///
/// Пишущий вариант появляется только у архива, лежащего в настоящей файловой
/// системе. Архив внутри архива открывается через временную копию, и записать
/// в него значило бы потерять изменения вместе с ней — такой остаётся только
/// для чтения, и панель честно показывает файловые операции недоступными.
class WritableZipTreeProvider extends ZipTreeProvider implements NodeEditor, FileContentReceiver, BatchedWrites {
  WritableZipTreeProvider._({
    required super.archivePath,
    required super.host,
    required super.index,
    required super.credentials,
    required StagingArea staging,
  }) : _staging = staging,
       super._();

  final StagingArea _staging;

  /// Каталог, куда ложится содержимое, пока архив не пересобран.
  StagedDirectory? _incoming;

  /// Новые записи: имя в архиве → файл с содержимым.
  final Map<String, String> _added = {};

  /// Новые каталоги: в zip это отдельные записи с косой чертой на конце.
  final Set<String> _addedDirs = {};

  /// Удалённые записи и поддеревья.
  final Set<String> _removed = {};

  /// Глубина работы: пересобирать архив внутри неё незачем.
  int _batchDepth = 0;

  bool get _dirty => _added.isNotEmpty || _addedDirs.isNotEmpty || _removed.isNotEmpty;

  /// В архив можно писать, но по одной записи это дорого: см. [BatchedWrites].
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(maxConcurrency: 1);

  // --- границы работы ---

  /// Пересборка архива: старые записи плюс новые, целиком заново. На большом
  /// архиве это дольше самой записи, поэтому окно операции показывает её
  /// отдельным этапом.
  @override
  String get writesStageName => 'repacking archive';

  @override
  Future<void> beginWrites() async => _batchDepth++;

  @override
  Future<void> endWrites() async {
    _batchDepth = _batchDepth > 0 ? _batchDepth - 1 : 0;
    if (_batchDepth == 0 && _dirty) {
      await _repack();
    }
  }

  /// Пересобирает архив, если работа закончилась. Внутри работы — копит.
  Future<void> _settle() async {
    if (_batchDepth == 0 && _dirty) {
      await _repack();
    }
  }

  // --- приём содержимого ---

  @override
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length}) async {
    _checkWritable(parent);

    final entryName = _entryNameFor(parent, name);
    final directory = await _incomingDirectory();
    // Имя во временном каталоге своё: в архиве могут лежать одноимённые
    // записи из разных каталогов.
    final staged = '${_added.length}-$name';

    return _StagedEntrySink(
      file: File(p.join(directory.path, staged)),
      onClosed: (path, size) async {
        _added[entryName] = path;
        _removed.remove(entryName);
        _putEntry(entryName, size: size, isDirectory: false);
        await _settle();
      },
    );
  }

  // --- примитивы дерева ---

  @override
  Future<FsNode?> lookup(DirectoryNode parent, String name) async {
    final entry = _entryOf(parent);
    final child = entry?.children[name];
    return child == null ? null : _nodeOf(child, parent);
  }

  @override
  Future<DirectoryNode> createDirectory(DirectoryNode parent, String name) async {
    _checkWritable(parent);
    if (name.isEmpty || name.contains('/')) {
      throw FsError('${pathOf(parent)}/$name', FsErrorKind.invalidName);
    }

    final entryName = _entryNameFor(parent, name);
    if (_entryOf(parent)?.children[name] != null) {
      throw FsError('${pathOf(parent)}/$name', FsErrorKind.alreadyExists);
    }

    _addedDirs.add('$entryName/');
    _removed.remove('$entryName/');
    _putEntry(entryName, size: 0, isDirectory: true);
    await _settle();

    return _nodeOf(_index.at(_segments('${pathOf(parent)}/$name'))!, parent) as DirectoryNode;
  }

  /// Копировать средствами архива нечего: содержимое всё равно распаковывается
  /// и запаковывается заново — этим и займётся поток.
  @override
  Future<bool> copyEntry(
    FsNode node,
    DirectoryNode destination,
    String name, {
    bool Function(int bytes)? onBytes,
  }) async => false;

  /// Переименование внутри архива — та же пересборка, что и копирование,
  /// поэтому движок обходится общим путём.
  @override
  Future<bool> renameEntry(FsNode node, DirectoryNode destination, String name) async => false;

  @override
  Future<void> deleteEntry(FsNode node) async {
    _remove(node);
    await _settle();
  }

  /// Поддерево уходит одним действием: пересобирать архив по файлу незачем.
  @override
  Future<bool> deleteTree(FsNode node) async {
    _remove(node);
    await _settle();
    return true;
  }

  /// Корзины у архива нет: удалённое из него удалено насовсем.
  @override
  Future<bool> trashEntry(FsNode node) async => false;

  @override
  bool isSameEntity(FsNode node, DirectoryNode destination) => pathOf(node.parentDirectory!) == pathOf(destination);

  @override
  bool isInsideSource(FsNode node, DirectoryNode destination) {
    if (node is! DirectoryNode) {
      return false;
    }
    final source = pathOf(node);
    final target = pathOf(destination);
    return target == source || target.startsWith('$source/');
  }

  @override
  Future<void> dispose() async {
    // Незаписанное не должно пропасть вместе с панелью: уходя из архива,
    // сперва дособираем.
    if (_dirty) {
      await _repack();
    }
    await _incoming?.dispose();
    _incoming = null;
    await super.dispose();
  }

  // --- внутреннее ---

  void _checkWritable(FsNode node) {
    if (_disposed) {
      throw FsError(archivePath, FsErrorKind.notSupported);
    }
  }

  Future<StagedDirectory> _incomingDirectory() async {
    return _incoming ??= await _staging.open('flex_commander_zip_write');
  }

  /// Имя записи в архиве: путь без ведущей косой черты.
  String _entryNameFor(DirectoryNode parent, String name) {
    final parentPath = pathOf(parent);
    final prefix = parentPath == '/' ? '' : '${parentPath.substring(1)}/';
    return '$prefix$name';
  }

  /// Заводит запись в оглавлении, чтобы панель увидела её сразу, не дожидаясь
  /// пересборки архива.
  void _putEntry(String entryName, {required int size, required bool isDirectory}) {
    final parts = entryName.split('/').where((part) => part.isNotEmpty).toList();
    var entry = _index.root;

    for (var i = 0; i < parts.length; i++) {
      final name = parts[i];
      final last = i == parts.length - 1;
      final existing = entry.children[name];

      if (existing != null && (!last || existing.isDirectory == isDirectory)) {
        if (last) {
          // Перезапись: размер меняется, остальное — то же самое.
          entry.children[name] = ZipEntry.file(name: name, entryName: entryName, size: size, modified: DateTime.now());
          return;
        }
        entry = existing;
        continue;
      }

      final child =
          last && !isDirectory
              ? ZipEntry.file(name: name, entryName: entryName, size: size, modified: DateTime.now())
              : ZipEntry.directory(name: name, entryName: '${parts.take(i + 1).join('/')}/', modified: DateTime.now());
      entry.children[name] = child;
      entry = child;
    }
  }

  /// Убирает запись из оглавления и запоминает, что её больше нет.
  void _remove(FsNode node) {
    final entry = _entryOf(node);
    if (entry == null) {
      throw FsError(node.pathString, FsErrorKind.notFound);
    }

    final name = entry.entryName.isEmpty ? _relativePathOf(node) : entry.entryName;
    _removed.add(entry.isDirectory ? _asDirectoryName(name) : name);
    _added.remove(name);
    _addedDirs.remove(_asDirectoryName(name));

    final parent = node.parentDirectory;
    final parentEntry = parent == null ? _index.root : _entryOf(parent);
    parentEntry?.children.remove(node.name);
  }

  String _relativePathOf(FsNode node) {
    final path = pathOf(node);
    return path.startsWith('/') ? path.substring(1) : path;
  }

  String _asDirectoryName(String name) => name.endsWith('/') ? name : '$name/';

  /// Собирает архив заново: старые записи, кроме удалённых и перезаписанных,
  /// плюс новые.
  ///
  /// Пересборка идёт во временный файл и подменяет исходный одним движением:
  /// оборванная на середине работа не должна оставить испорченный архив.
  ///
  /// Сама сборка — в отдельном изоляте (`repackZipArchive`): и разбор, и сжатие
  /// в `archive` синхронные, а идёт пересборка после записи, когда счётчик уже
  /// показал «готово». Замереть на ней значит выглядеть зависшим ровно тогда,
  /// когда человек ждёт конца работы.
  Future<void> _repack() async {
    final directory = await _incomingDirectory();
    final target = p.join(directory.path, 'repacked.zip');

    // Открытый на чтение архив держит файл: на Windows подменить его нельзя.
    await _closeArchive();

    await repackZipArchive(
      archivePath: archivePath,
      targetPath: target,
      removed: Set.of(_removed),
      addedDirectories: Set.of(_addedDirs),
      added: Map.of(_added),
    );

    await File(target).rename(archivePath);

    _added.clear();
    _addedDirs.clear();
    _removed.clear();
  }
}

/// Приёмник содержимого: пишет во временный файл и сообщает о готовой записи.
///
/// Своя обёртка, а не голый `IOSink`: архиву нужно узнать, что запись
/// дописана, — только после этого её можно класть в пересобираемый архив.
class _StagedEntrySink implements StreamSink<List<int>> {
  _StagedEntrySink({required this.file, required this.onClosed}) : _sink = file.openWrite();

  final File file;
  final Future<void> Function(String path, int size) onClosed;

  final IOSink _sink;
  final Completer<void> _done = Completer<void>();
  int _size = 0;

  @override
  void add(List<int> data) {
    _size += data.length;
    _sink.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _sink.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return _sink.addStream(
      stream.map((chunk) {
        _size += chunk.length;
        return chunk;
      }),
    );
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    await _sink.close();
    await onClosed(file.path, _size);
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}
