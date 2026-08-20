part of 'seven_zip_tree_provider.dart';

/// Архив, в который можно писать.
///
/// 7z — контейнер, а не файловая система: дописать в него запись «на месте»
/// нельзя. Но, в отличие от zip, пересобирает его не модуль, а сама программа —
/// нам остаётся выложить содержимое на диск и позвать её один раз на всю
/// работу. Границы работы сообщает движок операций ([BatchedWrites]); одиночное
/// действие вроде `F8` границ не имеет, и архив меняется сразу.
///
/// Пишущий вариант появляется только у архива, лежащего в настоящей файловой
/// системе. Архив внутри архива открывается через временную копию, и записать
/// в него значило бы потерять изменения вместе с ней — такой остаётся только
/// для чтения, и панель честно показывает файловые операции недоступными.
class WritableSevenZipTreeProvider extends SevenZipTreeProvider
    implements NodeEditor, FileContentReceiver, BatchedWrites {
  WritableSevenZipTreeProvider({
    required super.archivePath,
    required super.host,
    required super.listing,
    required super.cli,
    required super.credentials,
    required StagingArea staging,
    super.password,
  }) : _staging = staging;

  final StagingArea _staging;

  /// Каталог, где содержимое ждёт своей очереди. Раскладка в нём повторяет
  /// пути внутри архива: программа сохраняет имена такими, какими их получила,
  /// и `docs/readme.txt` в каталоге даст ровно такую запись.
  StagedDirectory? _incoming;

  /// Каталог для служебных списков. Отдельный от содержимого: файл со списком,
  /// положенный рядом с ним, мог бы совпасть по имени с чьим-нибудь файлом.
  StagedDirectory? _control;

  /// Записи, которые нужно добавить, — их же относительные пути в [_incoming].
  final Set<String> _added = {};

  /// Записи, которые нужно удалить.
  final Set<String> _removed = {};

  /// Глубина работы: звать программу внутри неё незачем.
  int _batchDepth = 0;

  bool get _dirty => _added.isNotEmpty || _removed.isNotEmpty;

  /// В архив можно писать, но по одной записи это дорого: см. [BatchedWrites].
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(maxConcurrency: 1);

  // --- границы работы ---

  @override
  Future<void> beginWrites() async => _batchDepth++;

  @override
  Future<void> endWrites() async {
    _batchDepth = _batchDepth > 0 ? _batchDepth - 1 : 0;
    if (_batchDepth == 0 && _dirty) {
      await _flush();
    }
  }

  /// Отдаёт накопленное программе, если работа закончилась. Внутри работы —
  /// копит.
  Future<void> _settle() async {
    if (_batchDepth == 0 && _dirty) {
      await _flush();
    }
  }

  // --- приём содержимого ---

  @override
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length}) async {
    _checkWritable();

    final entryName = _entryNameFor(parent, name);
    final staged = File(p.join((await _incomingDirectory()).path, entryName));
    await staged.parent.create(recursive: true);

    return _StagedEntrySink(
      file: staged,
      onClosed: (path, size) async {
        _added.add(entryName);
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
    _checkWritable();
    if (name.isEmpty || name.contains('/')) {
      throw FsError('${pathOf(parent)}/$name', FsErrorKind.invalidName);
    }

    final entryName = _entryNameFor(parent, name);
    if (_entryOf(parent)?.children[name] != null) {
      throw FsError('${pathOf(parent)}/$name', FsErrorKind.alreadyExists);
    }

    // Пустой каталог существует в архиве только собственной записью, и взяться
    // ей неоткуда, кроме как из такого же пустого каталога на диске.
    await Directory(p.join((await _incomingDirectory()).path, entryName)).create(recursive: true);

    _added.add(entryName);
    _removed.remove(entryName);
    _putEntry(entryName, size: 0, isDirectory: true);

    // Узел берётся до обращения к программе: она перечитает оглавление, и
    // запись в нём может оказаться другой — или не оказаться вовсе, если
    // программа не справилась. Тогда об этом скажет ошибка, а не падение.
    final created = _nodeOf(_listing.at(_segments('${pathOf(parent)}/$name'))!, parent) as DirectoryNode;
    await _settle();

    return created;
  }

  /// Копировать средствами архива нечего: содержимое всё равно распаковывается
  /// и запаковывается заново — этим и займётся поток.
  @override
  Future<bool> copyEntry(FsNode node, DirectoryNode destination, String name) async => false;

  /// Переименование внутри архива — та же работа, что и копирование, поэтому
  /// движок обходится общим путём.
  @override
  Future<bool> renameEntry(FsNode node, DirectoryNode destination, String name) async => false;

  @override
  Future<void> deleteEntry(FsNode node) async {
    _remove(node);
    await _settle();
  }

  /// Поддерево уходит одним действием: звать программу на каждый файл незачем.
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
    // сперва дописываем.
    if (_dirty) {
      await _flush();
    }
    await _incoming?.dispose();
    await _control?.dispose();
    _incoming = null;
    _control = null;
    await super.dispose();
  }

  // --- внутреннее ---

  void _checkWritable() {
    if (disposed) {
      throw FsError(archivePath, FsErrorKind.notSupported);
    }
  }

  Future<StagedDirectory> _incomingDirectory() async => _incoming ??= await _staging.open('flex_commander_7z_write');

  Future<StagedDirectory> _controlDirectory() async => _control ??= await _staging.open('flex_commander_7z_list');

  /// Имя записи в архиве: путь без ведущей косой черты.
  String _entryNameFor(DirectoryNode parent, String name) {
    final parentPath = pathOf(parent);
    final prefix = parentPath == '/' ? '' : '${parentPath.substring(1)}/';
    return '$prefix$name';
  }

  /// Заводит запись в оглавлении, чтобы панель увидела её сразу, не дожидаясь
  /// ответа программы.
  void _putEntry(String entryName, {required int size, required bool isDirectory}) {
    final parts = entryName.split('/').where((part) => part.isNotEmpty).toList();
    var entry = _listing.root;

    for (var i = 0; i < parts.length; i++) {
      final name = parts[i];
      final last = i == parts.length - 1;
      final existing = entry.children[name];

      if (existing != null && (!last || existing.isDirectory == isDirectory)) {
        if (last && !isDirectory) {
          // Перезапись: размер меняется, остальное — то же самое.
          entry.children[name] = SevenZipEntry.file(
            name: name,
            entryName: entryName,
            size: size,
            modified: DateTime.now(),
          );
          return;
        }
        entry = existing;
        continue;
      }

      final child =
          last && !isDirectory
              ? SevenZipEntry.file(name: name, entryName: entryName, size: size, modified: DateTime.now())
              : SevenZipEntry.directory(name: name, entryName: parts.take(i + 1).join('/'), modified: DateTime.now());
      entry.children[name] = child;
      entry = child;
    }
  }

  /// Убирает запись из оглавления и запоминает, что её больше нет.
  ///
  /// Поддерево перечисляется целиком: программа удаляет по именам, а имена все
  /// известны — оглавление прочитано. Так не приходится полагаться на
  /// подстановку, которой в разных сборках может и не быть.
  void _remove(FsNode node) {
    final entry = _entryOf(node);
    if (entry == null) {
      throw FsError(node.pathString, FsErrorKind.notFound);
    }

    _walk(entry, (child) {
      final name = child.entryName.isEmpty ? null : child.entryName;
      if (name == null) {
        return;
      }
      _removed.add(name);
      _added.remove(name);
    });

    // Достроенный по путям каталог своего имени в архиве не имеет: удалять
    // нечего, но из дерева он уйти должен вместе с содержимым.
    if (entry.entryName.isEmpty) {
      _removed.add(_relativePathOf(node));
    }

    final parent = node.parentDirectory;
    final parentEntry = parent == null ? _listing.root : _entryOf(parent);
    parentEntry?.children.remove(node.name);
  }

  String _relativePathOf(FsNode node) {
    final path = pathOf(node);
    return path.startsWith('/') ? path.substring(1) : path;
  }

  /// Отдаёт накопленное программе: сперва удаления, потом добавления.
  ///
  /// Списки уходят файлом, а не аргументами: работа на тысячу файлов иначе
  /// упёрлась бы в предел длины командной строки — а это ровно тот случай,
  /// когда пачка и нужна.
  Future<void> _flush() async {
    final removed = _removed.toList();
    final added = _added.toList();
    _removed.clear();
    _added.clear();

    try {
      if (removed.isNotEmpty) {
        await cli.delete(archivePath, listFile: await _writeList('remove', removed));
      }
      if (added.isNotEmpty) {
        final incoming = await _incomingDirectory();
        await cli.add(archivePath, workingDirectory: incoming.path, listFile: await _writeList('add', added));
      }
    } finally {
      // Оглавление перечитывается в любом случае: программа могла успеть
      // изменить архив и до неудачи, и показывать после этого прежнее дерево
      // нельзя.
      await refresh();
    }
  }

  /// Список имён файлом — в кодировке UTF-8, о которой программе сказано явно.
  Future<String> _writeList(String kind, List<String> names) async {
    final directory = await _controlDirectory();
    final file = File(p.join(directory.path, '$kind-${DateTime.now().microsecondsSinceEpoch}.txt'));
    await file.writeAsString(names.join('\n'), encoding: utf8);
    return file.path;
  }
}

/// Приёмник содержимого: пишет во временный файл и сообщает о готовой записи.
///
/// Своя обёртка, а не голый `IOSink`: архиву нужно узнать, что запись
/// дописана, — только после этого её можно отдавать программе.
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
