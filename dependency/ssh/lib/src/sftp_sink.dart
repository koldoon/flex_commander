import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:fc_api/fc_api.dart';

/// Приёмник байтов поверх открытого файла на сервере.
///
/// Запись идёт кусками по очереди, а не через `SftpFile.write`: тот пишет
/// с опережением, но ошибку записи роняет мимо возвращённого будущего — сбой
/// на середине выглядел бы как вечное ожидание конца копирования. Здесь каждый
/// кусок ждут, поэтому и обратное давление настоящее (движок не читает
/// источник быстрее, чем сервер принимает), и ошибка приходит туда, где её
/// разбирают.
class SftpFileSink implements StreamSink<List<int>> {
  SftpFileSink(this._file, this._path);

  final SftpFile _file;
  final String _path;

  final Completer<void> _done = Completer<void>();

  /// Очередь записей, поставленных через [add]: их некому ждать, поэтому
  /// очередь ждут при закрытии.
  Future<void> _queue = Future<void>.value();

  int _offset = 0;
  Object? _error;
  StackTrace? _stackTrace;
  bool _closed = false;

  @override
  void add(List<int> data) {
    if (_closed) {
      throw StateError('Приёмник уже закрыт: $_path');
    }
    _queue = _queue.then((_) => _write(data)).catchError(_remember);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _remember(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      // Поставленное через [add] пропускается вперёд: порядок байтов в файле
      // должен совпадать с порядком вызовов.
      await _queue;
      _throwIfFailed();
      await _write(chunk);
    }
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (_closed) {
      return _done.future;
    }
    _closed = true;
    try {
      await _queue;
      _throwIfFailed();
      await _file.close();
      if (!_done.isCompleted) {
        _done.complete();
      }
    } on Object catch (error, stackTrace) {
      // Файл на той стороне закрывается в любом случае: иначе он останется
      // висеть открытым до конца сессии.
      await _closeQuietly();
      if (!_done.isCompleted) {
        _done.completeError(error, stackTrace);
      }
      rethrow;
    }
    return _done.future;
  }

  Future<void> _write(List<int> data) async {
    if (data.isEmpty) {
      return;
    }
    final chunk = data is Uint8List ? data : Uint8List.fromList(data);
    try {
      await _file.writeBytes(chunk, offset: _offset);
    } on SftpError catch (error) {
      throw FsError(_path, FsErrorKind.io, error);
    }
    _offset += chunk.length;
  }

  void _remember(Object error, [StackTrace? stackTrace]) {
    _error ??= error;
    _stackTrace ??= stackTrace;
  }

  void _throwIfFailed() {
    final error = _error;
    if (error != null) {
      _error = null;
      Error.throwWithStackTrace(error, _stackTrace ?? StackTrace.current);
    }
  }

  Future<void> _closeQuietly() async {
    try {
      await _file.close();
    } on Object {
      // Разговор сейчас о том, из-за чего не записалось, а не о том, как
      // за этим убирали.
    }
  }
}
