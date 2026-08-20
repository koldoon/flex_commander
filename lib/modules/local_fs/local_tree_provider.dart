import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:fc_api/fc_api.dart';

import 'local_mapping.dart';
import 'local_listing.dart';

/// Провайдер дерева поверх локальной файловой системы.
///
/// В референсной реализации то же самое делалось запуском `ls` и `stat`, потому
/// что в AIR не было нормального API файловой системы. Здесь есть `dart:io`,
/// а внешние утилиты понадобятся позже — для копирования с прогрессом.
///
/// Реализует [NodeEditor], а не [TreeEditor]: обход, конфликты, прогресс и
/// выбор стратегии живут в движке переноса, а здесь — примитивы, каждый над
/// одним объектом. Байты для того же движка — обе половины сразу
/// ([FileContentProvider] и [FileContentReceiver]): локальная ФС и отдаёт
/// содержимое, и принимает.
class LocalTreeProvider implements TreeProvider, NodeEditor, FileContentProvider, FileContentReceiver {
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

  /// Локальная ФС умеет всё: переименование мгновенное, чтение с середины
  /// файла настоящее, дата при копировании сохраняется (`File.copy` переносит
  /// её вместе с содержимым), а пути можно отдавать внешним программам.
  ///
  /// Одновременных обходов диск выдерживает много: узкое место здесь не
  /// провайдер, а сам диск, и предел ему ставит настройка приложения.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    canRename: true,
    canSeek: true,
    preservesModified: true,
    realFileSystem: true,
    maxConcurrency: 16,
  );

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

    for (final current in providerPathNodes(node)) {
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

  /// Настоящий путь **самого объекта**: ссылки выше по цепочке развёрнуты,
  /// а сам объект — нет.
  ///
  /// Именно по нему выполняются операции над объектом: удалять и перемещать
  /// нужно саму ссылку, а не то, куда она ведёт. [physicalPathOf] для ссылки
  /// возвращает её цель — это верно для чтения, но не для изменения.
  String entityPathOf(FsNode node) {
    final parent = node.parent;
    if (parent == null) {
      return physicalPathOf(node);
    }
    return p.join(physicalPathOf(parent), node.name);
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
              : readDirectoryBlocking(path, includeHidden: includeHidden);

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
  Future<DirectoryNode> createDirectory(DirectoryNode parent, String name) async {
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

    final entry = await _describePath(path, name);
    if (entry == null) {
      throw FsError(path, FsErrorKind.io);
    }
    return nodeFromEntry(entry, parent) as DirectoryNode;
  }

  /// Содержимое каталога для обхода движком.
  ///
  /// Не [getDirectoryListing]: тот пишет результат в [DirectoryNode.nodes] и
  /// добавляет «..» — обход приёмника подменил бы то, что показывает панель.
  /// Читается всегда в этом же изоляте: на глубоком дереве изолят на каждый
  /// каталог стоил бы дороже, чем сами `stat`.
  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final entries = readDirectoryBlocking(physicalPathOf(dir), includeHidden: true);
    return [for (final entry in entries) nodeFromEntry(entry, dir)];
  }

  @override
  Future<FsNode?> lookup(DirectoryNode parent, String name) async {
    final path = p.join(physicalPathOf(parent), name);
    final entry = await _describePath(path, name);
    return entry == null ? null : nodeFromEntry(entry, parent);
  }

  /// Копия файла или ссылки. Ссылка копируется как ссылка: то, куда она ведёт,
  /// остаётся на месте.
  ///
  /// Каталоги создаёт и обходит движок — ему нужен прогресс по объектам,
  /// поэтому здесь на каталог возвращается false.
  @override
  Future<bool> copyEntry(FsNode node, DirectoryNode destination, String name) async {
    final source = entityPathOf(node);
    final target = p.join(physicalPathOf(destination), name);

    try {
      switch (FileSystemEntity.typeSync(source, followLinks: false)) {
        case FileSystemEntityType.link:
          await Link(target).create(await Link(source).target());
        case FileSystemEntityType.directory:
          return false;
        default:
          await File(source).copy(target);
      }
    } on FileSystemException catch (error) {
      throw fsErrorFrom(source, error);
    }
    return true;
  }

  /// Переименование — мгновенный перенос. Между дисками так нельзя: false,
  /// и движок скопирует объект и удалит исходный.
  @override
  Future<bool> renameEntry(FsNode node, DirectoryNode destination, String name) async {
    final source = entityPathOf(node);
    final target = p.join(physicalPathOf(destination), name);

    try {
      await _entityAt(source).rename(target);
      return true;
    } on FileSystemException catch (error) {
      if (_isCrossDevice(error)) {
        return false;
      }
      throw fsErrorFrom(source, error);
    }
  }

  /// Удаляет один объект: каталог к этому моменту пуст.
  @override
  Future<void> deleteEntry(FsNode node) async {
    // Путь самого объекта: удалять нужно ссылку, а не её цель.
    final path = entityPathOf(node);
    try {
      await _entityAt(path).delete();
    } on FileSystemException catch (error) {
      throw fsErrorFrom(path, error);
    }
  }

  @override
  Future<bool> deleteTree(FsNode node) async {
    await _deletePermanently(entityPathOf(node));
    return true;
  }

  @override
  Future<bool> trashEntry(FsNode node) async {
    await _moveToTrash(entityPathOf(node));
    return true;
  }

  @override
  bool isSameEntity(FsNode node, DirectoryNode destination) =>
      p.equals(entityPathOf(node), p.join(physicalPathOf(destination), node.name));

  @override
  bool isInsideSource(FsNode node, DirectoryNode destination) =>
      p.isWithin(p.normalize(entityPathOf(node)), p.normalize(p.join(physicalPathOf(destination), node.name)));

  /// Переносит объект в корзину пользователя.
  ///
  /// Перенос, а не удаление: корзина — это каталог `~/.Trash`, и объект должен
  /// оставаться восстановимым. Имя при совпадении разводится суффиксом, как
  /// это делает сама система.
  Future<void> _moveToTrash(String path) async {
    final trash = Directory(p.join(homePath, '.Trash'));
    try {
      if (!await trash.exists()) {
        await trash.create(recursive: true);
      }

      var target = p.join(trash.path, p.basename(path));
      var attempt = 2;
      while (await FileSystemEntity.type(target, followLinks: false) != FileSystemEntityType.notFound) {
        target = p.join(trash.path, '${p.basenameWithoutExtension(path)} $attempt${p.extension(path)}');
        attempt++;
      }

      await _entityAt(path).rename(target);
    } on FileSystemException catch (error) {
      // Перенос между дисками сам по себе невозможен: корзина живёт на диске
      // пользователя, а объект может быть на другом.
      throw fsErrorFrom(path, error);
    }
  }

  Future<void> _deletePermanently(String path) async {
    try {
      final entity = _entityAt(path);
      if (entity is Directory) {
        await entity.delete(recursive: true);
      } else {
        await entity.delete();
      }
    } on FileSystemException catch (error) {
      throw fsErrorFrom(path, error);
    }
  }

  /// Объект по пути без разыменования ссылок: удалять нужно саму ссылку,
  /// а не то, куда она ведёт.
  FileSystemEntity _entityAt(String path) {
    return switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      FileSystemEntityType.directory => Directory(path),
      FileSystemEntityType.link => Link(path),
      _ => File(path),
    };
  }

  /// Обход поддерева: всё, что лежит под [path], включая скрытое.
  ///
  /// Недоступный подкаталог обход **не прекращает**. Без обработчика ошибок
  /// первая же `EACCES` обрывает поток целиком, и всё, что стояло в очереди
  /// после неё, не доходит вовсе — размер каталога с одной закрытой папкой
  /// внутри оказывался меньше настоящего, причём молча. Так же ведёт себя `du`:
  /// ругается на недоступное и считает остальное.
  Stream<FileSystemEntity> _walk(String path) {
    return Directory(path)
        .list(recursive: true, followLinks: false)
        .handleError((Object _) {}, test: (error) => error is FileSystemException);
  }

  /// Обход поддерева ради счётчика: без построения узлов, зато с размерами —
  /// иначе не из чего показать долю в байтах.
  ///
  /// Размер стоит вызова `stat` на файл, то есть подсчёт вдвое дороже простого
  /// перечисления. Это цена честной доли и оценки времени, и платится она
  /// фоном, параллельно самой работе.
  @override
  Future<void> countEntries(FsNode node, void Function(int bytes) onEntry) async {
    final path = entityPathOf(node);
    onEntry(node.size > 0 ? node.size : 0);

    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.directory) {
        return;
      }
      await for (final entity in _walk(path)) {
        // Ссылка копируется ссылкой и байтов не переносит, каталог их не
        // имеет — считается только содержимое файлов.
        onEntry(entity is File ? await _lengthOf(entity) : 0);
      }
    } on FileSystemException {
      // Каталог мог исчезнуть или оказаться закрытым — считаем дальше.
    }
  }

  Future<int> _lengthOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      // Файл исчез между перечислением и вопросом о размере.
      return 0;
    }
  }

  /// Содержимое файла потоком.
  ///
  /// Путь берётся сам объект, а не его цель, но `dart:io` разыменует ссылку при
  /// открытии: ссылка, уехавшая в чужой провайдер, приезжает туда файлом —
  /// цели, на которую она указывает, там всё равно нет.
  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final path = entityPathOf(node);
    // Ошибка чтения приходит ошибкой потока, а не отсюда, — переводим её там,
    // где она возникает, иначе движку достанется исключение `dart:io`.
    return File(path).openRead(offset).handleError((Object error) {
      throw error is FileSystemException ? fsErrorFrom(path, error) : error;
    });
  }

  /// Приёмник для содержимого нового файла. [length] локальной ФС не нужен:
  /// место под файл она не резервирует.
  @override
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length}) async {
    final path = p.join(physicalPathOf(parent), name);
    try {
      return File(path).openWrite();
    } on FileSystemException catch (error) {
      throw fsErrorFrom(path, error);
    }
  }

  @override
  AsyncOperation<int> calculateSize(List<FsNode> nodes) {
    return TaskOperation<int>((op) async {
      var total = 0;

      for (final node in nodes) {
        op.checkCanceled();
        // Путь самого объекта: ссылка должна остаться ссылкой, иначе
        // содержимое каталога, на который она ведёт, попало бы в сумму дважды.
        final path = entityPathOf(node);

        if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.directory) {
          total += node.size > 0 ? node.size : 0;
          op.report(OperationProgress(processed: total, message: node.name));
          continue;
        }

        try {
          // Обход асинхронный: между объектами управление возвращается циклу
          // событий, поэтому интерфейс остаётся отзывчивым даже на большом
          // дереве, а отмена срабатывает сразу. Скрытые объекты считаются
          // наравне с остальными: размер каталога от того, показывает их
          // панель или нет, не меняется.
          await for (final entity in _walk(path)) {
            op.checkCanceled();
            if (entity is! File) {
              continue;
            }
            try {
              total += await entity.length();
            } on FileSystemException {
              // Файл исчез или закрыт — он просто не попадёт в сумму.
              continue;
            }
            op.report(OperationProgress(processed: total, message: node.name));
          }
        } on FileSystemException {
          // Сам каталог недоступен целиком: сумма останется без него.
          continue;
        }
      }

      return total;
    });
  }

  /// Ошибка «перенос между разными дисками» — единственный случай, когда
  /// переименование отвечает «не умею»: дальше движок скопирует объект
  /// и удалит исходный.
  bool _isCrossDevice(FileSystemException error) {
    final code = error.osError?.errorCode;
    return Platform.isWindows ? code == 17 : code == 18; // ERROR_NOT_SAME_DEVICE / EXDEV
  }

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
      return RawEntry(name: name, fileType: FileTypeFromIo.fromEntityType(type), linkTarget: linkTarget, broken: true);
    }

    if (stat.type == FileSystemEntityType.notFound) {
      return RawEntry(name: name, fileType: FileTypeFromIo.fromEntityType(type), linkTarget: linkTarget, broken: true);
    }

    final statType = FileTypeFromIo.fromEntityType(stat.type);
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
