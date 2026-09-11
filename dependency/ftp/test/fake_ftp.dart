import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ftp/fc_ftp.dart';
import 'package:path/path.dart' as p;

/// Подставной сервер на уровне [FtpApi].
///
/// Здесь проверяется **провайдер**: как он складывает дерево, что делает с
/// путями и во что переводит отказы. Сам протокол проверяется ниже — своим
/// сервером на сокетах (`fake_server.dart`) и живым (`real_ftp_test.dart`).
class FakeFtp implements FtpApi {
  FakeFtp({Map<String, List<int>> files = const {}, Set<String> directories = const {}, FtpFeatures? features})
    : _files = {...files},
      _directories = {'/', ...directories},
      _features = features ?? FtpFeatures(['MLST size*;type*;', 'REST STREAM', 'SIZE', 'MFMT']);

  final Map<String, List<int>> _files;
  final Set<String> _directories;
  final FtpFeatures _features;

  /// Что у сервера спросили — по порядку.
  final List<String> calls = [];

  /// Пути, на которых сервер отказывает: путь → род отказа.
  final Map<String, FsErrorKind> refusals = {};

  Map<String, List<int>> get files => _files;

  Set<String> get directories => _directories;

  @override
  FtpFeatures get features => _features;

  void _check(String path) {
    final refusal = refusals[path];
    if (refusal != null) {
      throw FsError(path, refusal);
    }
  }

  @override
  Future<List<FtpEntry>> listDirectory(String path) async {
    calls.add('list $path');
    _check(path);
    if (!_directories.contains(path)) {
      throw FsError(path, FsErrorKind.notFound);
    }

    final entries = <FtpEntry>[];
    for (final directory in _directories) {
      if (directory != path && p.posix.dirname(directory) == path) {
        entries.add(FtpEntry(name: p.posix.basename(directory), type: FileType.directory, mode: 0x1ED));
      }
    }
    for (final file in _files.entries) {
      if (p.posix.dirname(file.key) == path) {
        entries.add(
          FtpEntry(
            name: p.posix.basename(file.key),
            type: FileType.regular,
            size: file.value.length,
            mode: 0x1A4,
            owner: 'anonftp',
            modified: DateTime(2026, 9, 11),
          ),
        );
      }
    }
    return entries;
  }

  @override
  Future<FtpEntry?> stat(String path) async {
    calls.add('stat $path');
    _check(path);
    if (_directories.contains(path)) {
      return FtpEntry(name: p.posix.basename(path), type: FileType.directory, mode: 0x1ED);
    }
    final content = _files[path];
    if (content == null) {
      return null;
    }
    return FtpEntry(name: p.posix.basename(path), type: FileType.regular, size: content.length, mode: 0x1A4);
  }

  @override
  Future<Stream<List<int>>> openRead(String path, {int offset = 0}) async {
    calls.add('read $path${offset > 0 ? ' с $offset' : ''}');
    _check(path);
    final content = _files[path];
    if (content == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    return Stream.value(content.sublist(offset.clamp(0, content.length)));
  }

  @override
  Future<StreamSink<List<int>>> openWrite(String path) async {
    calls.add('write $path');
    _check(path);
    final controller = StreamController<List<int>>();
    final bytes = <int>[];
    final done = controller.stream.listen(bytes.addAll).asFuture<void>().then((_) => _files[path] = bytes);
    return _FakeSink(controller, done);
  }

  @override
  Future<void> makeDirectory(String path) async {
    calls.add('mkdir $path');
    _check(path);
    _directories.add(path);
  }

  @override
  Future<void> removeFile(String path) async {
    calls.add('rm $path');
    _check(path);
    if (_files.remove(path) == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
  }

  @override
  Future<void> removeDirectory(String path) async {
    calls.add('rmdir $path');
    _check(path);
    if (!_directories.remove(path)) {
      throw FsError(path, FsErrorKind.notFound);
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    calls.add('rename $from -> $to');
    _check(from);
    final content = _files.remove(from);
    if (content != null) {
      _files[to] = content;
      return;
    }
    if (_directories.remove(from)) {
      _directories.add(to);
      return;
    }
    throw FsError(from, FsErrorKind.notFound);
  }

  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

class _FakeSink implements StreamSink<List<int>> {
  _FakeSink(this._out, this._done);

  final StreamController<List<int>> _out;
  final Future<void> _done;

  @override
  void add(List<int> data) => _out.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _out.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _out.addStream(stream);

  @override
  Future<void> get done => _done;

  @override
  Future<void> close() async {
    await _out.close();
    await _done;
  }
}
