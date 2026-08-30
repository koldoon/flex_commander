import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:path/path.dart' as p;

/// Сервер в памяти: дерево путей и содержимое файлов.
///
/// Проверяет наши предположения о провайдере, а не о протоколе — за протокол
/// отвечает живой тест. Зато здесь можно устроить то, что на живом сервере
/// пришлось бы подстраивать: закрытый каталог, битую ссылку, отказ записи.
class FakeSftp implements SftpApi {
  FakeSftp({this.home = '/home/tester'}) {
    _nodes['/'] = _FakeNode(FileType.directory, mode: 0x41ED); // drwxr-xr-x
    for (final part in p.posix.split(home).skip(1)) {
      _current = p.posix.join(_current, part);
      _nodes[_current] = _FakeNode(FileType.directory, mode: 0x41ED);
    }
  }

  final String home;
  String _current = '/';

  final Map<String, _FakeNode> _nodes = {};

  /// Сколько раз о чём спрашивали: `stat /srv`. По ним видно лишние обращения.
  final List<String> calls = [];

  /// Пути, обращение к которым отвечает отказом.
  final Map<String, FsErrorKind> denied = {};

  bool closed = false;

  // --- наполнение ---------------------------------------------------------

  void directory(String path, {int mode = 0x41ED}) {
    _nodes[_norm(path)] = _FakeNode(FileType.directory, mode: mode);
  }

  void file(String path, String content, {int mode = 0x81A4, DateTime? modified}) {
    _nodes[_norm(path)] = _FakeNode(FileType.regular, bytes: utf8.encode(content), mode: mode, modified: modified);
  }

  void link(String path, String reference, {int mode = 0xA1FF}) {
    _nodes[_norm(path)] = _FakeNode(FileType.symbolicLink, mode: mode, linkTarget: reference);
  }

  bool has(String path) => _nodes.containsKey(_norm(path));

  String contentOf(String path) => utf8.decode(_nodes[_norm(path)]!.bytes!);

  // --- SftpApi ------------------------------------------------------------

  @override
  Future<SftpEntry?> stat(String path, {bool followLink = false}) async {
    calls.add('stat $path');
    _checkDenied(path);

    final resolved = _real(path, followLast: followLink);
    if (resolved == null) {
      return null;
    }
    final node = _nodes[resolved];
    return node == null ? null : _entry(p.posix.basename(resolved), node);
  }

  @override
  Future<List<SftpEntry>> listDirectory(String path) async {
    calls.add('list $path');
    _checkDenied(path);

    final directory = _real(path, followLast: true);
    final node = directory == null ? null : _nodes[directory];
    if (node == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    if (node.type != FileType.directory) {
      throw FsError(path, FsErrorKind.notADirectory);
    }

    return [
      for (final entry in _nodes.entries)
        if (entry.key != '/' && p.posix.dirname(entry.key) == directory)
          _entry(p.posix.basename(entry.key), entry.value),
    ];
  }

  @override
  Future<String?> readLink(String path) async {
    calls.add('readlink $path');
    final target = _real(path);
    return target == null ? null : _nodes[target]?.linkTarget;
  }

  @override
  Future<void> makeDirectory(String path) async {
    calls.add('mkdir $path');
    _checkDenied(path);

    final target = _real(path);
    if (target == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    if (_nodes.containsKey(target)) {
      throw FsError(path, FsErrorKind.alreadyExists);
    }
    if (_nodes[p.posix.dirname(target)]?.type != FileType.directory) {
      throw FsError(path, FsErrorKind.notFound);
    }
    _nodes[target] = _FakeNode(FileType.directory, mode: 0x41ED);
  }

  @override
  Future<void> createLink(String path, String reference) async {
    calls.add('symlink $path -> $reference');
    _checkDenied(path);

    final target = _real(path);
    if (target == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    if (_nodes.containsKey(target)) {
      throw FsError(path, FsErrorKind.alreadyExists);
    }
    _nodes[target] = _FakeNode(FileType.symbolicLink, linkTarget: reference);
  }

  @override
  Future<void> removeFile(String path) async {
    calls.add('remove $path');
    _checkDenied(path);

    final target = _real(path);
    final node = target == null ? null : _nodes[target];
    if (node == null || target == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    if (node.type == FileType.directory) {
      throw FsError(path, FsErrorKind.io);
    }
    _nodes.remove(target);
  }

  @override
  Future<void> removeDirectory(String path) async {
    calls.add('rmdir $path');
    _checkDenied(path);

    final target = _real(path);
    final node = target == null ? null : _nodes[target];
    if (node == null || target == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    if (node.type != FileType.directory) {
      throw FsError(path, FsErrorKind.notADirectory);
    }
    if (_childrenOf(target).isNotEmpty) {
      throw FsError(path, FsErrorKind.io);
    }
    _nodes.remove(target);
  }

  @override
  Future<void> rename(String from, String to) async {
    calls.add('rename $from -> $to');
    _checkDenied(from);
    _checkDenied(to);

    final source = _real(from) ?? _norm(from);
    final target = _real(to) ?? _norm(to);
    if (!_nodes.containsKey(source)) {
      throw FsError(from, FsErrorKind.notFound);
    }
    if (_nodes.containsKey(target)) {
      throw FsError(to, FsErrorKind.io);
    }

    for (final path in [source, ..._childrenOf(source)]) {
      final moved = path == source ? target : p.posix.join(target, p.posix.relative(path, from: source));
      _nodes[moved] = _nodes.remove(path)!;
    }
  }

  @override
  Future<Stream<List<int>>> openRead(String path, {int offset = 0}) async {
    calls.add('read $path');
    _checkDenied(path);

    final resolved = _real(path, followLast: true);
    final node = resolved == null ? null : _nodes[resolved];
    if (node?.bytes == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    final bytes = node!.bytes!;
    return Stream<List<int>>.value(bytes.sublist(offset.clamp(0, bytes.length)));
  }

  @override
  Future<bool> canWriteTo(String path) async {
    calls.add('canWriteTo $path');
    // Проба отвечает `false`, а не бросает: вопрос как раз о том, откажут ли.
    return denied[_norm(path)] == null;
  }

  @override
  Future<StreamSink<List<int>>> openWrite(String path) async {
    calls.add('write $path');
    _checkDenied(path);

    // Запись через ссылку идёт в цель; нового файла ещё нет — тогда путь как
    // набран.
    final target = _real(path, followLast: true) ?? _real(path) ?? _norm(path);
    if (_nodes[p.posix.dirname(target)]?.type != FileType.directory) {
      throw FsError(path, FsErrorKind.notFound);
    }

    final node = _FakeNode(FileType.regular, bytes: <int>[], mode: 0x81A4);
    _nodes[target] = node;
    return _FakeSink(node);
  }

  @override
  Future<String> absolute(String path) async => path == '.' ? home : _norm(path);

  @override
  Future<void> close() async {
    closed = true;
  }

  // --- внутреннее ---------------------------------------------------------

  void _checkDenied(String path) {
    final kind = denied[_norm(path)];
    if (kind != null) {
      throw FsError(path, kind);
    }
  }

  List<String> _childrenOf(String directory) => [
    for (final path in _nodes.keys)
      if (path != directory && p.posix.isWithin(directory, path)) path,
  ];

  /// Путь с развёрнутыми ссылками в промежуточных звеньях — так его понял бы
  /// настоящий сервер. [followLast] — разворачивать и последнее звено.
  ///
  /// null — по дороге что-то не нашлось.
  String? _real(String path, {bool followLast = false}) {
    final segments = p.posix.split(_norm(path));
    var current = '/';

    for (var i = 1; i < segments.length; i++) {
      current = p.posix.join(current, segments[i]);
      if (i == segments.length - 1 && !followLast) {
        return current;
      }
      final resolved = _follow(current);
      if (resolved == null) {
        return null;
      }
      current = resolved;
    }
    return current;
  }

  /// Идёт по ссылке до настоящего объекта; null — цели нет.
  String? _follow(String path) {
    var current = path;
    for (var step = 0; step < 8; step++) {
      final node = _nodes[current];
      if (node == null) {
        return null;
      }
      final reference = node.linkTarget;
      if (node.type != FileType.symbolicLink || reference == null) {
        return current;
      }
      current = _norm(reference.startsWith('/') ? reference : p.posix.join(p.posix.dirname(current), reference));
    }
    return null;
  }

  SftpEntry _entry(String name, _FakeNode node) => SftpEntry(
    name: name,
    type: node.type,
    size: node.type == FileType.directory ? FsNode.unknownSize : (node.bytes?.length ?? FsNode.unknownSize),
    mode: node.mode,
    modified: node.modified,
  );

  static String _norm(String path) => p.posix.normalize(path.startsWith('/') ? path : '/$path');
}

class _FakeNode {
  _FakeNode(this.type, {this.bytes, this.mode = 0, this.modified, this.linkTarget});

  final FileType type;
  List<int>? bytes;
  final int mode;
  final DateTime? modified;
  final String? linkTarget;
}

class _FakeSink implements StreamSink<List<int>> {
  _FakeSink(this._node);

  final _FakeNode _node;
  final Completer<void> _done = Completer<void>();

  @override
  void add(List<int> data) => _node.bytes!.addAll(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}
