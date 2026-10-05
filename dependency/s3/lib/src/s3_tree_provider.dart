import 'dart:async';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

import 's3_address.dart';
import 's3_api.dart';
import 's3_client.dart';
import 's3_encoding.dart';
import 's3_errors.dart';
import 's3_upload_sink.dart';
import 's3_xml.dart';

/// Хранилище S3 — источником: корзины, префиксы каталогами, объекты файлами
/// (`docs/spec/s3.md`).
///
/// Дерево собирается из того, что отдаёт [S3Api]; о HTTP, подписи и XML
/// источник не знает ничего — и проверяется подставкой, как FTP
/// (`ftp.md`, §4.1).
///
/// Путь: `/` — корзины, `/b` — корзина, `/b/a/c` — префикс `a/c/` или объект
/// `a/c`.
class S3TreeProvider implements TreeProvider, NodeEditor, FileContentProvider, FileContentReceiver, ProviderLifecycle {
  S3TreeProvider({required this.target, required S3Api api, Strings? strings})
    : _api = api,
      strings = strings ?? StringsRegistry();

  final S3Target target;
  final S3Api _api;

  /// Строки на языке человека: ход чтения видно в строке состояния панели.
  final Strings strings;

  /// Копия на стороне сервера — до этого размера одним запросом.
  static const int singleCopyLimit = 5 * 1024 * 1024 * 1024;

  /// Часть многочастной копии.
  static const int copyPart = 512 * 1024 * 1024;

  /// Подключается по адресу и отдаёт хранилище.
  ///
  /// Ключ проверяется **первым же запросом** — тем, который и так нужен:
  /// листинг корзины из адреса или список корзин. Отвергнут — забыть и
  /// спросить снова, как неверный пароль у FTP (§6).
  static Future<TreeProvider> open(
    Uri address, {
    required Credentials credentials,
    Strings? strings,
    S3Api Function(S3Target target, String accessKey, String secret)? connect,
  }) async {
    final target = S3Target.parse(address);
    final said = strings ?? StringsRegistry();
    final makeApi =
        connect ?? (S3Target t, String key, String secret) => S3Client(t, accessKey: key, secretKey: secret);

    // Ключа в адресе нет — спрашиваются оба поля; есть — только секрет.
    final fields = [
      if (target.accessKey == null) CredentialField(name: CredentialField.user.name, label: said.tr('Access key ID')),
      CredentialField(name: CredentialField.password.name, label: said.tr('Secret access key'), secret: true),
    ];
    var request = CredentialRequest(
      realm: target.realm,
      title: said.tr('S3 authentication'),
      message: target.display,
      fields: fields,
    );

    String? key = target.accessKey;
    String? secret = target.secretFromAddress;

    while (true) {
      if (secret == null || key == null) {
        final answer = await credentials.obtain(request);
        if (answer == null) {
          throw FsError(target.display, FsErrorKind.permissionDenied);
        }
        key = target.accessKey ?? answer[CredentialField.user.name] ?? '';
        secret = answer.password ?? '';
      }

      final api = makeApi(target, key, secret);
      try {
        final bucket = target.bucket;
        if (bucket != null) {
          await api.listObjects(bucket, prefix: target.prefix.isEmpty ? '' : '${target.prefix}/', maxKeys: 1);
        } else {
          await api.listBuckets();
        }
        return S3TreeProvider(target: target, api: api, strings: said);
      } on FsError catch (error) {
        await api.close();
        if (!credentialRejected(error)) {
          rethrow;
        }
        credentials.forget(request.realm);
        request = request.retrying();
        secret = null;
        if (target.accessKey == null) {
          key = null;
        }
      }
    }
  }

  @override
  String get scheme => target.schemeName;

  @override
  String get homePath {
    final bucket = target.bucket;
    if (bucket == null) {
      return '/';
    }
    return target.prefix.isEmpty ? '/$bucket' : '/$bucket/${target.prefix}';
  }

  late final DirectoryNode _root = DirectoryNode(provider: this, name: '/');

  @override
  DirectoryNode get rootDirectory => _root;

  /// * переименование — да: объект переезжает копией на стороне сервера и
  ///   удалением, а «нет» здесь погасило бы и переименование, и запись архива
  ///   обратно (§12);
  /// * чтение с середины — `Range`, поэтому `zip` поверх S3 достаётся даром;
  /// * дату копия не сохраняет: её ставит хранилище;
  /// * работ — восемь: HTTP держит много запросов, а крупный файл и так идёт
  ///   один и грузится частями внутри своего приёмника.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    canRename: true,
    canSeek: true,
    preservesModified: false,
    realFileSystem: false,
    maxConcurrency: 8,
  );

  @override
  String pathOf(FsNode node) {
    final query = target.query;
    return '${target.authority}${remotePathOf(node)}${query.isEmpty ? '' : '?$query'}';
  }

  /// Путь внутри хранилища: `/корзина/ключ`.
  String remotePathOf(FsNode node) {
    final names = visiblePathNodes(node).map((node) => node.name).where((name) => name != '/');
    return names.isEmpty ? '/' : '/${names.join('/')}';
  }

  /// Корзина и ключ по узлу. У каталога ключ кончается `/`; у корзины — пуст.
  (String bucket, String key) _locate(FsNode node) {
    final segments = p.posix.split(remotePathOf(node)).skip(1).toList();
    if (segments.isEmpty) {
      throw FsError(remotePathOf(node), FsErrorKind.notSupported);
    }
    final key = segments.skip(1).join('/');
    return (segments.first, node is DirectoryNode && key.isNotEmpty ? '$key/' : key);
  }

  /// Глубина узла: 0 — корень, 1 — корзина.
  int _depth(FsNode node) => p.posix.split(remotePathOf(node)).length - 1;

  /// Разбор пути — **за один оборот**: последний сегмент проверяется сразу и
  /// объектом, и префиксом, параллельно; промежуточные не проверяются вовсе
  /// (`ftp.md`, §3.8).
  @override
  Operation<String, FsNode?> resolvePath() {
    return TaskOperation<String, FsNode?>((op, path) async {
      final normalized = _normalize(target.stripAuthorityAndQuery(path));
      if (normalized == '/') {
        return _root;
      }
      final segments = p.posix.split(normalized).skip(1).toList();
      DirectoryNode parent = _root;
      for (var i = 0; i < segments.length - 1; i++) {
        parent = DirectoryNode(provider: this, name: segments[i], parent: parent);
      }
      op.checkCanceled();
      return lookup(parent, segments.last);
    });
  }

  @override
  Future<FsNode?> lookup(DirectoryNode parent, String name) async {
    if (identical(parent, _root) || _depth(parent) == 0) {
      return _bucketAt(name);
    }
    final (bucket, dirKey) = _locate(parent);
    final key = '$dirKey$name';
    // Объект и префикс — одним оборотом. Каталог побеждает: панели в него
    // ходят, а объект с тем же именем, что и префикс, — редкость.
    final results = await Future.wait([
      _api.listObjects(bucket, prefix: '$key/', maxKeys: 1),
      _api.headObject(bucket, key),
    ]);
    final page = results[0] as S3Page;
    if (page.objects.isNotEmpty || page.prefixes.isNotEmpty) {
      return DirectoryNode(provider: this, name: name, parent: parent);
    }
    final object = results[1] as S3Object?;
    if (object == null) {
      return null;
    }
    return FileNode(provider: this, name: name, parent: parent, size: object.size, modified: object.modified);
  }

  Future<FsNode?> _bucketAt(String name) async {
    try {
      await _api.listObjects(name, maxKeys: 1);
      return DirectoryNode(provider: this, name: name, parent: _root);
    } on FsError catch (error) {
      if (error.kind == FsErrorKind.notFound) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      final dir = params.dir;
      op.report(message: strings.tr('Reading {path}…', args: {'path': pathOf(dir)}));
      final children = await _children(dir, op: op);
      final nodes = <FsNode>[
        if (dir.parentDirectory != null) ParentDirNode(dir),
        for (final node in children)
          if (params.includeHidden || !node.name.startsWith('.')) node,
      ];
      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) => _children(dir);

  /// Содержимое уровня — страницами, с отменой между ними и ходом работы:
  /// корзина на миллион ключей — обычное дело (§9).
  Future<List<FsNode>> _children(DirectoryNode dir, {OperationContext? op}) async {
    if (_depth(dir) == 0) {
      return _buckets();
    }
    final (bucket, dirKey) = _locate(dir);
    final nodes = <FsNode>[];
    String? token;
    do {
      op?.checkCanceled();
      final page = await _api.listObjects(bucket, prefix: dirKey, token: token);
      for (final prefix in page.prefixes) {
        final name = _lastSegment(prefix.substring(0, prefix.length - 1));
        if (name.isNotEmpty) {
          nodes.add(DirectoryNode(provider: this, name: name, parent: dir));
        }
      }
      for (final object in page.objects) {
        // Маркер самого каталога (`dir/` в листинге `dir/`) — не строка: это он
        // сам (разведка §3).
        if (object.key == dirKey) {
          continue;
        }
        final name = _lastSegment(object.key);
        if (name.isEmpty || !sendableKey(object.key)) {
          continue;
        }
        nodes.add(FileNode(provider: this, name: name, parent: dir, size: object.size, modified: object.modified));
      }
      token = page.nextToken;
      if (token != null) {
        op?.report(message: strings.tr('Reading {path}… {count}', args: {'path': pathOf(dir), 'count': nodes.length}));
      }
    } while (token != null);
    return nodes;
  }

  /// Корзины. Ключ, которому не дали права на весь счёт, всё же видит корзину
  /// из адреса — её и показываем, а не отказ (§6).
  Future<List<FsNode>> _buckets() async {
    try {
      return [
        for (final bucket in await _api.listBuckets())
          DirectoryNode(provider: this, name: bucket.name, parent: _root, modified: bucket.created),
      ];
    } on FsError catch (error) {
      final own = target.bucket;
      if (error.kind == FsErrorKind.permissionDenied && own != null) {
        return [DirectoryNode(provider: this, name: own, parent: _root)];
      }
      rethrow;
    }
  }

  /// Ссылок в S3 нет.
  @override
  Operation<LinkNode, FsNode?> resolveLink() => TaskOperation<LinkNode, FsNode?>((op, link) async => null);

  static void _checkName(String name) {
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/')) {
      throw FsError(name, FsErrorKind.invalidName);
    }
  }

  /// Каталог — маркер `имя/` нулевой длины: пустых каталогов в S3 иначе не
  /// бывает, а копия дерева создаёт каталоги первыми (§12). В корне — корзина.
  @override
  Future<DirectoryNode> createDirectory(DirectoryNode parent, String name) async {
    _checkName(name);
    if (_depth(parent) == 0) {
      await _api.createBucket(name);
      return DirectoryNode(provider: this, name: name, parent: _root);
    }
    if (await lookup(parent, name) != null) {
      throw FsError(p.posix.join(remotePathOf(parent), name), FsErrorKind.alreadyExists);
    }
    final (bucket, dirKey) = _locate(parent);
    await _api.putObject(bucket, '$dirKey$name/', Uint8List(0));
    return DirectoryNode(provider: this, name: name, parent: parent);
  }

  /// Копия объекта средствами сервера: байты через нас не идут. Больше 5 ГиБ —
  /// многочастной копией, частями по 512 МиБ.
  @override
  Future<bool> copyEntry(
    FsNode node,
    DirectoryNode destination,
    String name, {
    bool Function(int bytes)? onBytes,
  }) async {
    if (!identical(destination.provider, this) || node is! FileNode || _depth(destination) == 0) {
      return false;
    }
    _checkName(name);
    final (fromBucket, fromKey) = _locate(node);
    final (toBucket, dirKey) = _locate(destination);
    final toKey = '$dirKey$name';
    if (node.size <= singleCopyLimit) {
      await _api.copyObject(fromBucket, fromKey, toBucket, toKey);
      if (onBytes != null && !onBytes(node.size < 0 ? 0 : node.size)) {
        throw const OperationCanceled();
      }
      return true;
    }
    final id = await _api.createMultipartUpload(toBucket, toKey);
    try {
      final parts = <S3Part>[];
      var number = 1;
      for (var first = 0; first < node.size; first += copyPart) {
        final last = (first + copyPart > node.size ? node.size : first + copyPart) - 1;
        final etag = await _api.uploadPartCopy(fromBucket, fromKey, toBucket, toKey, id, number, first, last);
        parts.add(S3Part(number: number++, etag: etag));
        if (onBytes != null && !onBytes(last - first + 1)) {
          throw const OperationCanceled();
        }
      }
      await _api.completeMultipartUpload(toBucket, toKey, id, parts);
      return true;
    } catch (_) {
      await _api.abortMultipartUpload(toBucket, toKey, id).catchError((Object _) {});
      rethrow;
    }
  }

  /// Объект переезжает копией и удалением; префикс — нет: это столько копий,
  /// сколько под ним ключей, и это уже работа движка (§12).
  @override
  Future<bool> renameEntry(FsNode node, DirectoryNode destination, String name) async {
    if (!identical(destination.provider, this) || node is! FileNode || _depth(destination) == 0) {
      return false;
    }
    if (!await copyEntry(node, destination, name)) {
      return false;
    }
    final (bucket, key) = _locate(node);
    await _api.deleteObject(bucket, key);
    return true;
  }

  @override
  Future<void> deleteEntry(FsNode node) async {
    if (_depth(node) == 1) {
      final (bucket, _) = _locate(node);
      await _api.deleteBucket(bucket);
      return;
    }
    final (bucket, key) = _locate(node);
    // У каталога — маркер; его может и не быть, и это не ошибка.
    await _api.deleteObject(bucket, key);
  }

  /// Удалить поддерево пачками по тысяче ключей: поштучно это тысяча запросов
  /// на тысячу файлов. Хранилище без пачек (Google Storage) — поштучно.
  @override
  Future<bool> deleteTree(FsNode node) async {
    if (node is! DirectoryNode) {
      await deleteEntry(node);
      return true;
    }
    final (bucket, prefix) = _locate(node);
    String? token;
    do {
      final page = await _api.listObjects(bucket, prefix: prefix, delimiter: null, token: token);
      final keys = [for (final object in page.objects) object.key];
      if (keys.isNotEmpty) {
        await _deleteKeys(bucket, keys);
      }
      token = page.nextToken;
    } while (token != null);
    if (_depth(node) == 1) {
      await _api.deleteBucket(bucket);
    }
    return true;
  }

  bool _noBatches = false;

  Future<void> _deleteKeys(String bucket, List<String> keys) async {
    if (!_noBatches) {
      try {
        final failures = await _api.deleteObjects(bucket, keys);
        if (failures.isNotEmpty) {
          final first = failures.first;
          throw s3Error(first.key, S3Failure(status: 0, code: first.code, message: first.message));
        }
        return;
      } on FsError catch (error) {
        if (error.kind != FsErrorKind.notSupported) {
          rethrow;
        }
        _noBatches = true;
      }
    }
    for (var i = 0; i < keys.length; i += 8) {
      await Future.wait([for (final key in keys.skip(i).take(8)) _api.deleteObject(bucket, key)]);
    }
  }

  /// Корзины для удалённого нет.
  @override
  Future<FsNode?> trashEntry(FsNode node) async => null;

  @override
  bool isSameEntity(FsNode node, DirectoryNode destination) =>
      p.posix.equals(remotePathOf(node), p.posix.join(remotePathOf(destination), node.name));

  @override
  bool isInsideSource(FsNode node, DirectoryNode destination) => p.posix.isWithin(
    p.posix.normalize(remotePathOf(node)),
    p.posix.normalize(p.posix.join(remotePathOf(destination), node.name)),
  );

  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    if (node.size >= 0 && offset >= node.size && offset > 0) {
      return const Stream<List<int>>.empty();
    }
    final (bucket, key) = _locate(node);
    return _api.getObject(bucket, key, offset: offset);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length}) async {
    _checkName(name);
    if (_depth(parent) == 0) {
      throw FsError(name, FsErrorKind.notSupported);
    }
    final (bucket, dirKey) = _locate(parent);
    return S3UploadSink(_api, bucket, '$dirKey$name', length: length);
  }

  @override
  Future<void> dispose() => _api.close();

  static String _lastSegment(String key) {
    final slash = key.lastIndexOf('/');
    return slash < 0 ? key : key.substring(slash + 1);
  }

  static String _normalize(String path) {
    final normalized = p.posix.normalize(path.isEmpty ? '/' : path);
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }
}
