import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

import 'ftp_address.dart';
import 'ftp_api.dart';
import 'ftp_connection.dart';
import 'ftp_mapping.dart';
import 'ftp_over_connection.dart';

/// Файлы чужого сервера по FTP.
///
/// Дерево собирается из того, что отдаёт [FtpApi]; о протоколе провайдер не
/// знает ничего — и потому проверяется подставкой, без сервера
/// (`docs/spec/ftp.md`, §4.1).
class FtpTreeProvider implements TreeProvider, NodeEditor, FileContentProvider, FileContentReceiver, ProviderLifecycle {
  FtpTreeProvider({required this.target, required FtpApi ftp, String? homePath, Strings? strings})
    : _ftp = ftp,
      homePath = homePath ?? '/',
      strings = strings ?? StringsRegistry();

  /// Схема пути; `ftps` — её же второе имя, модуль объявляет обе.
  static const String schemeName = FtpTarget.scheme;

  final FtpTarget target;
  final FtpApi _ftp;

  /// Строки на языке человека: вехи чтения видно в строке состояния панели.
  final Strings strings;

  /// Подключается по адресу и отдаёт дерево сервера.
  static Future<TreeProvider> open(
    Uri address, {
    required Credentials credentials,
    Strings? strings,
    bool allowUnknownCertificate = false,
  }) async {
    final target = FtpTarget.parse(address);
    final said = strings ?? StringsRegistry();

    var request = CredentialRequest(
      realm: target.realm,
      title: said.tr('FTP authentication'),
      message: target.display,
      fields: const [CredentialField.password],
    );

    // Анонимный вход и пароль прямо в адресе спрашивать не о чем.
    String? password = target.passwordFromAddress ?? (target.isAnonymous ? FtpTarget.anonymousPassword : null);

    while (true) {
      if (password == null) {
        final answer = await credentials.obtain(request);
        if (answer == null) {
          throw FsError(target.display, FsErrorKind.permissionDenied);
        }
        password = answer.password ?? '';
      }

      final secret = password;
      Future<FtpConnection> connect() =>
          FtpConnection.open(target, password: secret, onBadCertificate: allowUnknownCertificate ? (_) => true : null);

      try {
        final connection = await connect();
        return FtpTreeProvider(
          target: target,
          // Соединение, замолчавшее посреди передачи, поднимается заново тем
          // же паролем: человека об этом не спрашивают второй раз.
          ftp: FtpOverConnection(connection, reopen: connect),
          homePath: target.path.isEmpty ? '/' : target.path,
          strings: said,
        );
      } on FsError catch (error) {
        // Повтор — забота спрашивающего: только он знает, подошёл ли секрет
        // (`Credentials`, докблок).
        final retryable = error.kind == FsErrorKind.permissionDenied && !target.isAnonymous;
        if (!retryable) {
          rethrow;
        }
        credentials.forget(request.realm);
        request = request.retrying();
        password = null;
      }
    }
  }

  @override
  final String homePath;

  @override
  String get scheme => schemeName;

  late final DirectoryNode _root = DirectoryNode(provider: this, name: '/');

  @override
  DirectoryNode get rootDirectory => _root;

  /// Переименование на сервере мгновенное (`RNFR`/`RNTO`), чтение с середины
  /// настоящее (`REST`). Дату копия не сохраняет: байты идут потоком, а
  /// времена — нет; поставить её отдельно умеет `MFMT`, но это уже не копия.
  /// Пути отдавать внешним программам нельзя — машина чужая.
  ///
  /// **Работа ровно одна.** У FTP один управляющий канал, и передача его
  /// занимает: второй обход не ускорил бы ничего, а только встал бы в очередь
  /// (`docs/spec/ftp.md`, §5).
  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
    canRename: true,
    canSeek: _ftp.features.restart,
    preservesModified: false,
    realFileSystem: false,
    maxConcurrency: 1,
  );

  /// Путь внутри провайдера — с началом адреса, чтобы строка целиком
  /// разбиралась обратно в тот же сервер: `ftp://user@host/pub`.
  @override
  String pathOf(FsNode node) => '${target.authority}${remotePathOf(node)}';

  /// Путь на сервере: то, что уходит в команду.
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
        final node = await _nodeAt(p.posix.join(remotePathOf(parent), name), name, parent);
        if (node == null) {
          return null;
        }
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
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      final dir = params.dir;
      op.report(message: strings.tr('Reading {path}…', args: {'path': pathOf(dir)}));

      final entries = await _ftp.listDirectory(remotePathOf(dir));
      op.checkCanceled();

      final nodes = <FsNode>[if (dir.parentDirectory != null) ParentDirNode(dir)];
      for (final entry in entries) {
        if (!params.includeHidden && entry.name.startsWith('.')) {
          continue;
        }
        nodes.add(_nodeFrom(entry, dir));
      }

      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final entries = await _ftp.listDirectory(remotePathOf(dir));
    return [for (final entry in entries) _nodeFrom(entry, dir)];
  }

  /// Куда ведёт ссылка, сервер говорит прямо в списке — отдельной команды для
  /// этого у FTP нет. Цель разбирается тем же разбором пути.
  @override
  Operation<LinkNode, FsNode?> resolveLink() {
    return TaskOperation<LinkNode, FsNode?>((op, link) async {
      final reference = link.reference;
      if (reference.isEmpty) {
        return null;
      }
      final absolute =
          p.posix.isAbsolute(reference)
              ? reference
              : p.posix.normalize(p.posix.join(p.posix.dirname(remotePathOf(link)), reference));
      final resolved = await resolvePath().run(absolute);
      op.checkCanceled();
      link.target = resolved;
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
    // Существование проверяется до действия: отдельного кода «уже существует»
    // у FTP нет — сервер отвечает общим отказом, и по нему не отличить занятое
    // имя от нехватки прав. Та же причина, что и по SFTP.
    if (await _ftp.stat(path) != null) {
      throw FsError(path, FsErrorKind.alreadyExists);
    }

    await _ftp.makeDirectory(path);
    return DirectoryNode(provider: this, name: name, parent: parent);
  }

  /// Копии средствами сервера у FTP нет — `SITE COPY` есть не у всех и
  /// стандартом не является. false — и движок скопирует потоком.
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
    await _ftp.rename(remotePathOf(node), p.posix.join(remotePathOf(destination), name));
    return true;
  }

  @override
  Future<void> deleteEntry(FsNode node) async {
    final path = remotePathOf(node);
    // Каталог к этому моменту пуст: движок обошёл его сам.
    if (node is DirectoryNode) {
      await _ftp.removeDirectory(path);
    } else {
      await _ftp.removeFile(path);
    }
  }

  /// Удаления поддерева одним действием у FTP нет: рекурсию ведёт движок —
  /// заодно и показывает ход работы.
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
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) =>
      _ftp.openRead(remotePathOf(node), offset: offset);

  /// [length] серверу не нужен: места под файл FTP не резервирует.
  @override
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length}) =>
      _ftp.openWrite(p.posix.join(remotePathOf(parent), name));

  @override
  Future<void> dispose() => _ftp.close();

  // --- узлы ---

  Future<FsNode?> _nodeAt(String path, String name, DirectoryNode parent) async {
    final entry = await _ftp.stat(path);
    return entry == null
        ? null
        : _nodeFrom(
          FtpEntry(
            name: name,
            type: entry.type,
            size: entry.size,
            mode: entry.mode,
            owner: entry.owner,
            group: entry.group,
            modified: entry.modified,
            linkTarget: entry.linkTarget,
            permissions: entry.permissions,
          ),
          parent,
        );
  }

  FsNode _nodeFrom(FtpEntry entry, DirectoryNode parent) {
    if (entry.isDirectory) {
      return DirectoryNode(provider: this, name: entry.name, parent: parent, modified: entry.modified);
    }
    if (entry.isLink) {
      // Каталог ли цель, сервер в списке не говорит: у `MLSD` для этого нет
      // факта, а `LIST` показывает права самой ссылки. Разворачивать её ради
      // строки списка значило бы обращение на каждую ссылку в каталоге.
      return LinkNode(
        provider: this,
        name: entry.name,
        parent: parent,
        reference: entry.linkTarget,
        modified: entry.modified,
      );
    }
    return FileNode(
      provider: this,
      name: entry.name,
      parent: parent,
      size: entry.size,
      modified: entry.modified,
      attributes: attributesOf(entry.mode, FileType.regular),
    );
  }

  static String _normalize(String path) {
    final normalized = p.posix.normalize(path.isEmpty ? '/' : path);
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }
}
