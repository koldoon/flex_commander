import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:path/path.dart' as p;

import 'sftp_api.dart';
import 'sftp_mapping.dart';
import 'ssh_address.dart';
import 'ssh_connection.dart';

/// Дерево на чужой машине по SFTP.
///
/// Первый источник, который сам себе корень: архив — звено пути, а сервер —
/// начало другого пути, и панель встаёт на него целиком. Всё остальное — как
/// у локальной файловой системы: примитивы здесь, обход и прогресс в движке
/// переноса.
///
/// Путей два вида — видимый (`//user@host/srv`, он же уходит в настройки) и
/// путь на сервере (`/srv`). Отдельного «физического» пути, как у локального
/// провайдера, здесь нет и не нужно: ссылки на той стороне разворачивает сам
/// сервер, а удаление и переименование он к последней ссылке в пути не
/// применяет — то есть ровно то поведение, которое нам и нужно.
class SftpTreeProvider
    implements TreeProvider, NodeEditor, FileContentProvider, FileContentReceiver, ProviderLifecycle {
  SftpTreeProvider({required this.target, required SftpApi sftp, required this.homePath, SshConnection? connection})
    : _sftp = sftp,
      _connection = connection;

  /// Схема пути. `sftp` — её же второе имя: модуль объявляет оба.
  static const String schemeName = 'ssh';

  /// Подключается по адресу и отдаёт дерево сервера.
  static Future<TreeProvider> open(Uri address, {required Credentials credentials, String? sshDirectory}) async {
    final target = SshTarget.parse(address);
    if (target.host.isEmpty || target.user.isEmpty) {
      // Ни хоста, ни имени пользователя взять неоткуда: это не адрес.
      throw FsError(address.toString(), FsErrorKind.invalidAddress);
    }

    final connection = await SshConnection.open(target: target, credentials: credentials, sshDirectory: sshDirectory);

    return SftpTreeProvider(
      target: target,
      sftp: connection.sftp,
      homePath: connection.homePath,
      connection: connection,
    );
  }

  final SshTarget target;
  final SftpApi _sftp;
  final SshConnection? _connection;

  /// Дом пользователя **на сервере**: сюда открывается панель и сюда
  /// разворачивается тильда.
  @override
  final String homePath;

  @override
  String get scheme => schemeName;

  late final DirectoryNode _root = DirectoryNode(provider: this, name: '/');

  @override
  DirectoryNode get rootDirectory => _root;

  /// Переименование внутри сервера мгновенное, чтение с середины файла
  /// настоящее (`read(offset:)` уходит в протокол как есть). Дату копия не
  /// сохраняет: байты приезжают потоком, а времена — нет. Пути отдавать
  /// внешним программам нельзя — машина чужая.
  ///
  /// Одновременных работ — две: чужому серверу десяток параллельных обходов
  /// не нужен, а один сделал бы подсчёт размера заметно медленнее самой
  /// работы.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    canRename: true,
    canSeek: true,
    preservesModified: false,
    realFileSystem: false,
    // Четыре, а не два: канал у SFTP один, но запросы в нём идут вперемешку, и
    // OpenSSH держит в полёте до шестидесяти четырёх. Четыре — скромно даже для
    // домашнего сервера, а задержку они прячут почти целиком.
    maxConcurrency: 4,
  );

  /// Путь внутри провайдера — с началом адреса, чтобы строка целиком
  /// разбиралась обратно в тот же сервер: `ssh://user@host/srv`.
  @override
  String pathOf(FsNode node) => '${target.authority}${remotePathOf(node)}';

  /// Путь на сервере: то, что уходит в протокол.
  ///
  /// Имя цели ссылки в него не входит — путь показывает, как сюда пришли,
  /// а разворачивает ссылку сервер.
  String remotePathOf(FsNode node) {
    final names = visiblePathNodes(node).map((node) => node.name).where((name) => name != '/');
    return names.isEmpty ? '/' : '/${names.join('/')}';
  }

  @override
  Operation<String, FsNode?> resolvePath() {
    return TaskOperation<String, FsNode?>((op, path) async {
      final normalized = _normalize(target.stripAuthority(path));
      if (normalized == '/') {
        return _root;
      }

      final segments = p.posix.split(normalized).skip(1).toList();
      DirectoryNode parent = _root;

      for (var i = 0; i < segments.length; i++) {
        op.checkCanceled();

        final name = segments[i];
        final childPath = p.posix.join(remotePathOf(parent), name);
        final node = await _nodeAt(childPath, name, parent);
        if (node == null) {
          return null;
        }

        if (i == segments.length - 1) {
          return node;
        }
        if (node is! DirectoryNode) {
          // Промежуточный элемент пути не каталог. Ссылка на каталог годится:
          // разворачиваем и идём дальше, видимый путь по-прежнему через неё.
          if (node is LinkNode && node.isDirectoryLink) {
            final resolvedTarget = await _resolveTarget(node);
            if (resolvedTarget is DirectoryNode) {
              parent = resolvedTarget;
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
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      final dir = params.dir;
      final includeHidden = params.includeHidden;
      final path = remotePathOf(dir);
      op.report(message: 'Reading ${pathOf(dir)}…');

      final entries = await _sftp.listDirectory(path);
      op.checkCanceled();

      final nodes = <FsNode>[if (dir.parentDirectory != null) ParentDirNode(dir)];
      for (final entry in entries) {
        if (!includeHidden && entry.name.startsWith('.')) {
          continue;
        }
        op.checkCanceled();
        nodes.add(await _nodeFrom(entry, p.posix.join(path, entry.name), dir));
      }

      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final path = remotePathOf(dir);
    final entries = await _sftp.listDirectory(path);
    return [for (final entry in entries) await _nodeFrom(entry, p.posix.join(path, entry.name), dir)];
  }

  @override
  Operation<LinkNode, FsNode?> resolveLink() {
    return TaskOperation<LinkNode, FsNode?>((op, link) async {
      final resolved = await _resolveTarget(link);
      op.checkCanceled();
      return resolved;
    });
  }

  @override
  Future<FsNode?> lookup(DirectoryNode parent, String name) =>
      _nodeAt(p.posix.join(remotePathOf(parent), name), name, parent);

  @override
  Future<DirectoryNode> createDirectory(DirectoryNode parent, String name) async {
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/')) {
      throw FsError(name, FsErrorKind.invalidName);
    }

    final path = p.posix.join(remotePathOf(parent), name);
    // Существование проверяется до действия: в третьей версии протокола нет
    // кода «уже существует», сервер отвечает общим отказом — по нему не
    // отличить занятое имя от нехватки прав.
    if (await _sftp.stat(path) != null) {
      throw FsError(path, FsErrorKind.alreadyExists);
    }

    await _sftp.makeDirectory(path);

    final created = await _nodeAt(path, name, parent);
    if (created is! DirectoryNode) {
      throw FsError(path, FsErrorKind.io);
    }
    return created;
  }

  /// Копии средствами сервера у SFTP нет: содержимое всё равно идёт через нас.
  /// false — и движок скопирует потоком, читая и записывая по одному
  /// соединению.
  @override
  Future<bool> copyEntry(
    FsNode node,
    DirectoryNode destination,
    String name, {
    bool Function(int bytes)? onBytes,
  }) async => false;

  @override
  Future<bool> renameEntry(FsNode node, DirectoryNode destination, String name) async {
    if (!identical(destination.provider, this)) {
      // Другая машина: одним действием туда не переехать.
      return false;
    }

    final from = remotePathOf(node);
    final to = p.posix.join(remotePathOf(destination), name);
    try {
      await _sftp.rename(from, to);
      return true;
    } on FsError catch (error) {
      // Разные файловые системы на самом сервере выглядят как общий отказ —
      // отдельного кода для этого в протоколе нет. Отвечаем «не умею», и
      // движок скопирует объект и удалит исходный. Про права и отсутствие
      // объекта сервер говорит внятно — такое молчать нельзя.
      if (error.kind == FsErrorKind.io) {
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteEntry(FsNode node) async {
    final path = remotePathOf(node);
    // Каталог к этому моменту пуст: движок обошёл его сам. Ссылка удаляется
    // как ссылка — последнюю ссылку в пути сервер не разворачивает.
    if (node is DirectoryNode) {
      await _sftp.removeDirectory(path);
    } else {
      await _sftp.removeFile(path);
    }
  }

  /// Удаления поддерева одним действием в протоколе нет: рекурсию ведёт
  /// движок — заодно и показывает ход работы.
  @override
  Future<bool> deleteTree(FsNode node) async => false;

  /// Корзины на сервере нет.
  @override
  Future<bool> trashEntry(FsNode node) async => false;

  @override
  bool isSameEntity(FsNode node, DirectoryNode destination) =>
      p.posix.equals(remotePathOf(node), p.posix.join(remotePathOf(destination), node.name));

  @override
  bool isInsideSource(FsNode node, DirectoryNode destination) => p.posix.isWithin(
    p.posix.normalize(remotePathOf(node)),
    p.posix.normalize(p.posix.join(remotePathOf(destination), node.name)),
  );

  @override
  Future<void> countEntries(FsNode node, void Function(int bytes) onEntry) async {
    onEntry(node.size > 0 ? node.size : 0);
    if (node is! DirectoryNode) {
      return;
    }
    await _walk(remotePathOf(node), (entry, path) => onEntry(entry.size > 0 ? entry.size : 0));
  }

  @override
  Operation<List<FsNode>, int> calculateSize() {
    return TaskOperation<List<FsNode>, int>((op, nodes) async {
      var total = 0;

      for (final node in nodes) {
        op.checkCanceled();

        if (node is! DirectoryNode) {
          total += node.size > 0 ? node.size : 0;
          op.report(itemsTransferred: total, message: node.name);
          continue;
        }

        await _walk(remotePathOf(node), (entry, path) {
          // Отмена проверяется на каждом объекте: обход чужого дерева бывает
          // долгим, и ждать его конца, чтобы прерваться, незачем.
          op.checkCanceled();
          if (entry.isDirectory || entry.isLink) {
            // Ссылка уезжает ссылкой и байтов не переносит, у каталога их нет.
            return;
          }
          total += entry.size > 0 ? entry.size : 0;
          op.report(itemsTransferred: total, message: node.name);
        });
      }

      return total;
    });
  }

  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) =>
      _sftp.openRead(remotePathOf(node), offset: offset);

  /// [length] серверу не нужен: место под файл SFTP не резервирует.
  @override
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length}) =>
      _sftp.openWrite(p.posix.join(remotePathOf(parent), name));

  @override
  Future<void> dispose() async {
    final connection = _connection;
    if (connection != null) {
      await connection.close();
    } else {
      await _sftp.close();
    }
  }

  /// Обход поддерева на сервере.
  ///
  /// Недоступный подкаталог обход не прекращает: одна закрытая папка внутри не
  /// должна уменьшать посчитанный размер всего дерева — так же ведёт себя `du`.
  /// Исключение из [visit] наружу проходит: этим движок и отмена прекращают
  /// подсчёт.
  Future<void> _walk(String path, void Function(SftpEntry entry, String path) visit) async {
    final List<SftpEntry> entries;
    try {
      entries = await _sftp.listDirectory(path);
    } on FsError {
      return;
    }

    for (final entry in entries) {
      final childPath = p.posix.join(path, entry.name);
      visit(entry, childPath);
      if (entry.isDirectory) {
        await _walk(childPath, visit);
      }
    }
  }

  /// Узел по пути; null — по этому пути ничего нет.
  Future<FsNode?> _nodeAt(String path, String name, FsNode parent) async {
    final entry = await _sftp.stat(path);
    if (entry == null) {
      return null;
    }
    return _nodeFrom(
      SftpEntry(
        name: name,
        type: entry.type,
        size: entry.size,
        mode: entry.mode,
        modified: entry.modified,
        accessed: entry.accessed,
      ),
      path,
      parent,
    );
  }

  /// Запись — узлом. Про ссылку спрашивается отдельно: куда она ведёт и что
  /// там лежит.
  ///
  /// Это два лишних обращения к серверу на каждую ссылку в каталоге. Цена
  /// того стоит: без типа цели ссылка на каталог не откроется по Enter и уедет
  /// в конец списка при сортировке «каталоги вперёд».
  Future<FsNode> _nodeFrom(SftpEntry entry, String path, FsNode parent) async {
    if (!entry.isLink) {
      return nodeFromEntry(entry, parent, this);
    }

    final reference = await _sftp.readLink(path);
    final resolvedTarget = await _sftp.stat(path, followLink: true);

    return nodeFromEntry(
      SftpEntry(
        name: entry.name,
        type: entry.type,
        size: entry.size,
        mode: entry.mode,
        modified: entry.modified,
        accessed: entry.accessed,
        linkTarget: reference ?? '',
      ),
      parent,
      this,
      linkTargetType: resolvedTarget?.type,
    );
  }

  /// Разрешает ссылку: цель становится **дочерним узлом самой ссылки**.
  ///
  /// Так дерево помнит, как пользователь сюда попал: переход наверх вернёт в
  /// каталог, где ссылка лежит, а не туда, куда она ведёт. Цепочки
  /// разворачивать не нужно — сервер разворачивает их сам, и закольцованная
  /// ссылка возвращается ошибкой, а не бесконечностью.
  Future<FsNode?> _resolveTarget(LinkNode link) async {
    final path = remotePathOf(link);
    final entry = await _sftp.stat(path, followLink: true);
    if (entry == null) {
      return null;
    }

    final reference = link.reference;
    final resolvedTarget = nodeFromEntry(
      SftpEntry(
        name: reference.isEmpty ? link.name : p.posix.basename(reference),
        type: entry.type,
        size: entry.size,
        mode: entry.mode,
        modified: entry.modified,
        accessed: entry.accessed,
      ),
      link,
      this,
    );

    link.target = resolvedTarget;
    return resolvedTarget;
  }

  /// Путь в канонический вид. Относительный считается от дома пользователя —
  /// так же, как его понял бы сам сервер.
  String _normalize(String path) => p.posix.normalize(path.startsWith('/') ? path : p.posix.join(homePath, path));
}
