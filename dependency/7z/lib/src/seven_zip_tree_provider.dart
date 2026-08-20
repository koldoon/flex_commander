import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:path/path.dart' as p;

import 'seven_zip_cli.dart';
import 'seven_zip_listing.dart';

part 'writable_seven_zip_tree_provider.dart';

/// Оглавление и пароль, которым оно открылось.
class _UnlockedListing {
  _UnlockedListing(this.listing, this.password);

  final SevenZipListing listing;
  final String? password;
}

/// Архив 7z как дерево.
///
/// Формат читается не своими силами, а программой `7z`: упаковщика 7z в Dart
/// нет вовсе, и написать его — это контейнер плюс LZMA, то есть месяцы. MC и
/// прочие менеджеры поступают ровно так же. Отсюда и цена: без установленной
/// программы модуль честно говорит, чего ему не хватает.
///
/// Открывается архив только там, где у него есть настоящий путь: программе
/// нужен файл, по которому можно ходить. Архив внутри архива или на сервере
/// сперва оказывается во временном файле — тот же мост, что у zip.
class SevenZipTreeProvider implements TreeProvider, FileContentProvider, ProviderLifecycle {
  SevenZipTreeProvider({
    required this.archivePath,
    required FsNode host,
    required SevenZipListing listing,
    required this.cli,
    required this.credentials,
    String? password,
    LocalCopySession? session,
  }) : _host = host,
       _listing = listing,
       _password = password,
       _session = session;

  /// Схема для строк пути: `…/archive.7z:7z:/inner/doc.txt`.
  static const String schemeName = '7z';

  /// Расширения, которые открываются этим провайдером.
  ///
  /// Только свой формат, хотя программа умеет и rar, и iso: модуль называется
  /// по формату, а не по инструменту, и чужие форматы — это чужие модули со
  /// своими особенностями.
  static const Set<String> extensions = {'7z'};

  /// Открывает архив: читает оглавление и строит по нему дерево.
  static Future<TreeProvider> open(
    FsNode host, {
    required StagingArea staging,
    required SevenZipCli cli,
    required Credentials credentials,
    void Function(int bytes)? onBytes,
  }) async {
    final session = LocalCopySession(staging, prefix: 'flex_commander_7z');

    try {
      final path = await session.localPathOf(host, onBytes: onBytes);
      final unlocked = await _list(path, cli: cli, credentials: credentials, name: host.name);

      if (session.copied == 0) {
        // Архив лежит в настоящей файловой системе: в него можно и писать.
        return WritableSevenZipTreeProvider(
          archivePath: path,
          host: host,
          listing: unlocked.listing,
          cli: cli,
          credentials: credentials,
          password: unlocked.password,
          staging: staging,
        );
      }

      // Архив, открытый через временную копию (внутри другого архива или на
      // сервере), остаётся только для чтения: изменения ушли бы вместе с
      // копией. Сессия хранится, чтобы копию было кому убрать.
      return SevenZipTreeProvider(
        archivePath: path,
        host: host,
        listing: unlocked.listing,
        cli: cli,
        credentials: credentials,
        password: unlocked.password,
        session: session,
      );
    } on Object {
      // Битый архив, нет программы, отмена: копия не должна пережить неудачу.
      await session.purge();
      rethrow;
    }
  }

  /// Читает оглавление, спрашивая пароль, пока он не подойдёт.
  ///
  /// У архива с шифрованным оглавлением без пароля не видно даже имён:
  /// программа отвечает «Cannot open encrypted archive», и это приходит сюда
  /// отказом в доступе. Повтор — забота спрашивающего: только он знает, подошёл
  /// ли пароль.
  static Future<_UnlockedListing> _list(
    String path, {
    required SevenZipCli cli,
    required Credentials credentials,
    required String name,
  }) async {
    var request = CredentialRequest(realm: realmOf(path), title: 'Encrypted archive', message: name);
    String? password;

    while (true) {
      try {
        return _UnlockedListing(await cli.list(path, password: password), password);
      } on FsError catch (error) {
        if (error.kind != FsErrorKind.permissionDenied) {
          rethrow;
        }
      }

      if (password != null) {
        // Этот не подошёл: забыть, чтобы следующий вопрос был настоящим
        // вопросом, а не тем же ответом из памяти.
        credentials.forget(request.realm);
        request = request.retrying();
      }

      password = (await credentials.obtain(request))?.password;
      if (password == null || password.isEmpty) {
        throw FsError(path, FsErrorKind.permissionDenied);
      }
    }
  }

  /// Адрес, под которым помнится пароль к этому архиву.
  static String realmOf(String archivePath) => '$schemeName:$archivePath';

  /// Путь к файлу архива в локальной файловой системе.
  final String archivePath;

  /// Программа, которой читается и пишется архив.
  final SevenZipCli cli;

  /// Откуда берётся пароль, когда он нужен.
  final Credentials credentials;

  /// Пароль, которым архив открылся; null — архив без пароля.
  ///
  /// Живёт, пока открыт архив: спрашивать его на каждую запись значило бы
  /// показывать окно на каждый файл — программа-то запускается заново.
  String? _password;

  /// Узел, над которым провайдер смонтирован: файл архива в чужом дереве.
  final FsNode _host;

  /// Временная копия архива; null — архив и так лежал в локальной ФС.
  final LocalCopySession? _session;

  /// Оглавление, прочитанное при открытии. Перечитывается после записи.
  SevenZipListing _listing;

  SevenZipListing get listing => _listing;

  bool _disposed = false;

  @override
  String get scheme => schemeName;

  /// Настоящих путей внутри архива нет, а читать запись с середины программа
  /// не умеет: содержимое отдаётся с начала и целиком.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(maxConcurrency: 1);

  @override
  late final DirectoryNode rootDirectory = DirectoryNode(provider: this, name: '/', parent: _host);

  /// Корень архива: другого «дома» у него нет.
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
  AsyncOperation<FsNode?> resolvePath(String path) {
    return TaskOperation<FsNode?>((op) async {
      FsNode node = rootDirectory;
      SevenZipEntry entry = _listing.root;

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
  AsyncOperation<List<FsNode>> getDirectoryListing(DirectoryNode dir, {bool includeHidden = false}) {
    return TaskOperation<List<FsNode>>((op) async {
      final entry = _entryOf(dir);
      if (entry == null || !entry.isDirectory) {
        throw FsError(dir.pathString, FsErrorKind.notFound);
      }

      final nodes = <FsNode>[
        // «..» из корня архива ведёт наружу — туда, где лежит сам архив.
        if (dir.parentDirectory != null) ParentDirNode(dir),
        for (final child in _childrenOf(entry, includeHidden: includeHidden)) _nodeOf(child, dir),
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

  /// Ссылок внутри архива мы не показываем: разрешать нечего.
  @override
  AsyncOperation<FsNode?> resolveLink(LinkNode link) => CompletedOperation<FsNode?>(null);

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
  AsyncOperation<int> calculateSize(List<FsNode> nodes) {
    return TaskOperation<int>((op) async {
      var total = 0;
      for (final node in nodes) {
        op.checkCanceled();
        final entry = _entryOf(node);
        if (entry == null) {
          continue;
        }
        _walk(entry, (child) => total += child.isDirectory ? 0 : child.size);
        op.report(OperationProgress(processed: total, message: node.name));
      }
      return total;
    });
  }

  /// Содержимое файла из архива — потоком, прямо из программы.
  ///
  /// Это лучше, чем у zip, где запись распаковывается в память целиком: здесь
  /// байты идут по мере распаковки. Но и здесь нельзя начать с середины —
  /// начало приходится вычитать и выбросить.
  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final entry = _entryOf(node);
    if (entry == null || entry.isDirectory) {
      throw FsError(node.pathString, FsErrorKind.notFound);
    }
    if (entry.encrypted && _password == null) {
      // Записи бывают зашифрованы поодиночке — оглавление при этом читается без
      // пароля. Спрашиваем до чтения: поток иначе сорвался бы на первом байте.
      final credential = await credentials.obtain(
        CredentialRequest(realm: realmOf(archivePath), title: 'Encrypted archive', message: _host.name),
      );
      _password = credential?.password;
      if (_password == null) {
        throw FsError(node.pathString, FsErrorKind.permissionDenied);
      }
    }

    final content = _forgetWrongPassword(cli.read(archivePath, entry.entryName, password: _password));
    return offset <= 0 ? content : _skip(content, offset);
  }

  /// Пароль не подошёл — забыть его, чтобы следующее чтение спросило заново.
  ///
  /// Повторить прямо здесь нельзя: поток уже отдан наружу, и часть байтов
  /// читатель мог получить. Зато второй попытки не будет с тем же неверным
  /// паролем — а это и есть разница между «спросили ещё раз» и «архив
  /// сломался».
  Stream<List<int>> _forgetWrongPassword(Stream<List<int>> source) async* {
    try {
      // `await for`, а не `yield*`: тот пересылает ошибки потока читателю мимо
      // `try`, и поймать их здесь было бы нечем.
      await for (final chunk in source) {
        yield chunk;
      }
    } on FsError catch (error) {
      if (error.kind == FsErrorKind.permissionDenied) {
        credentials.forget(realmOf(archivePath));
        _password = null;
      }
      rethrow;
    }
  }

  /// Выбрасывает первые [offset] байт: программа отдаёт запись только целиком.
  Stream<List<int>> _skip(Stream<List<int>> source, int offset) async* {
    var left = offset;
    await for (final chunk in source) {
      if (left <= 0) {
        yield chunk;
        continue;
      }
      if (chunk.length <= left) {
        left -= chunk.length;
        continue;
      }
      yield chunk.sublist(left);
      left = 0;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _session?.purge();
  }

  bool get disposed => _disposed;

  /// Заменяет оглавление прочитанным заново — после того, как архив изменили.
  Future<void> refresh() async {
    _listing = await cli.list(archivePath, password: _password);
  }

  SevenZipEntry? _entryOf(FsNode node) => _listing.at(_segments(pathOf(node)));

  Iterable<SevenZipEntry> _childrenOf(SevenZipEntry entry, {required bool includeHidden}) {
    final children = entry.children.values.where((child) => includeHidden || !child.name.startsWith('.')).toList();
    // Порядок оглавления произвольный, а сортировкой заведует панель: отдаём
    // хотя бы устойчивый.
    children.sort((a, b) => a.name.compareTo(b.name));
    return children;
  }

  void _walk(SevenZipEntry entry, void Function(SevenZipEntry entry) visit) {
    visit(entry);
    for (final child in entry.children.values) {
      _walk(child, visit);
    }
  }

  /// Путь внутри архива разбирается своими силами: разделитель здесь всегда
  /// косая черта, каким бы ни был он в системе, а `package:path` на своей
  /// платформе разберёт `/docs` как корень с именем.
  List<String> _segments(String path) => path.split('/').where((name) => name.isNotEmpty && name != '.').toList();

  FsNode _nodeOf(SevenZipEntry entry, FsNode parent) {
    final attributes =
        entry.mode == 0
            ? const FileAttributes.unknown()
            : FileAttributes(
              mode: entry.mode,
              modeString:
                  '${entry.isDirectory ? FileType.directory.attributeChar : FileType.regular.attributeChar}'
                  '${_modeString(entry.mode)}',
            );

    if (entry.isDirectory) {
      return DirectoryNode(
        provider: this,
        name: entry.name,
        parent: parent,
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

  /// «rwxr-xr-x» из режима доступа: режим в архиве — обычное число.
  static String _modeString(int mode) {
    const flags = ['r', 'w', 'x'];
    final buffer = StringBuffer();
    for (var bit = 8; bit >= 0; bit--) {
      buffer.write(mode & (1 << bit) != 0 ? flags[2 - bit % 3] : '-');
    }
    return buffer.toString();
  }
}
