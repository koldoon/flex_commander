import 'dart:async';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 's3_api.dart';
import 's3_xml.dart';

/// Приёмник загрузки в S3 (`docs/spec/s3.md`, §11).
///
/// * Маленький файл известного размера — **одним PUT** на `close()`.
/// * Остальное — **многочастно**: загрузка заводится, когда наполнилась первая
///   часть, и части уходят до [maxInFlight] разом. Источник на это время встаёт
///   на паузу — память ограничена `(maxInFlight + 1) × partSize`.
/// * `close()` — собрать объект из частей (`Complete`); не вышло — отменить.
/// * `abort()` — оборвать запросы в полёте и отменить загрузку на сервере:
///   брошенные части не видны в листинге и лежат, пока их не уберут, — а
///   считаются в счёт каждый месяц.
class S3UploadSink implements StreamSink<List<int>>, AbortableSink {
  S3UploadSink(this._api, this.bucket, this.key, {int? length, this.maxInFlight = 4, int? partSize})
    : partSize = partSize ?? partSizeFor(length),
      _length = length;

  final S3Api _api;
  final String bucket;
  final String key;
  final int? _length;
  final int maxInFlight;
  final int partSize;

  /// Наименьшая часть, которую принимает S3 (кроме последней).
  static const int minPart = 8 * 1024 * 1024;

  /// Часть при неизвестном размере: 16 МиБ × 10 000 частей — 160 ГБ.
  static const int unknownPart = 16 * 1024 * 1024;

  /// Частей у загрузки не больше десяти тысяч — часть растёт вместе с файлом.
  static int partSizeFor(int? length) {
    if (length == null) {
      return unknownPart;
    }
    const mib = 1024 * 1024;
    final needed = (length / 10000 / mib).ceil() * mib;
    return needed > minPart ? needed : minPart;
  }

  BytesBuilder _buffer = BytesBuilder(copy: false);
  String? _uploadId;
  Future<String>? _starting;
  int _nextPart = 1;
  final Map<int, String> _etags = {};
  final Set<Future<void>> _inFlight = {};
  final List<S3Abort> _aborts = [];
  Object? _failure;
  StackTrace? _failureStack;
  bool _finished = false;
  StreamSubscription<List<int>>? _subscription;
  final Completer<void> _done = Completer<void>();

  @override
  Future<void> get done => _done.future;

  @override
  void add(List<int> data) {
    if (_finished) {
      throw StateError('приёмник уже закрыт');
    }
    _buffer.add(data);
    _cutParts();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _fail(error, stackTrace);

  /// Принимает поток сам — ради паузы: пока частей в полёте предел, источник
  /// стоит, и `asyncMap` движка не убегает вперёд.
  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final finished = Completer<void>();
    _subscription = stream.listen(
      (data) {
        _buffer.add(data);
        _cutParts();
        if (_inFlight.length >= maxInFlight) {
          _subscription?.pause();
          unawaited(Future.any(_inFlight).whenComplete(() => _subscription?.resume()));
        }
      },
      onError: (Object error, StackTrace stack) {
        _fail(error, stack);
        _subscription?.cancel();
        if (!finished.isCompleted) {
          finished.completeError(error, stack);
        }
      },
      onDone: () {
        if (!finished.isCompleted) {
          finished.complete();
        }
      },
      cancelOnError: true,
    );
    return finished.future;
  }

  /// Наполнилась часть — отправить.
  void _cutParts() {
    while (_buffer.length >= partSize && _failure == null) {
      final bytes = _buffer.takeBytes();
      final part = Uint8List.sublistView(bytes, 0, partSize);
      final rest = Uint8List.sublistView(bytes, partSize);
      _buffer = BytesBuilder(copy: false)..add(rest);
      _send(part);
    }
  }

  void _send(Uint8List part) {
    final number = _nextPart++;
    final abort = S3Abort();
    _aborts.add(abort);
    late final Future<void> flight;
    flight = () async {
      try {
        final id = await (_starting ??= _api.createMultipartUpload(bucket, key).then((id) => _uploadId = id));
        if (abort.aborted) {
          return;
        }
        _etags[number] = await _api.uploadPart(bucket, key, id, number, part, abort: abort);
      } catch (error, stack) {
        _fail(error, stack);
      } finally {
        _inFlight.remove(flight);
        _aborts.remove(abort);
      }
    }();
    _inFlight.add(flight);
  }

  void _fail(Object error, [StackTrace? stack]) {
    _failure ??= error;
    _failureStack ??= stack;
  }

  @override
  Future<void> close() async {
    if (_finished) {
      return done;
    }
    _finished = true;
    try {
      await _waitParts();
      _throwIfFailed();
      if (_uploadId == null && _starting == null) {
        // Многочастная так и не понадобилась: всё уместилось в одну часть.
        await _api.putObject(bucket, key, _buffer.takeBytes());
      } else {
        // Последняя часть бывает меньше наименьшей — так и задумано.
        if (_buffer.length > 0) {
          _send(_buffer.takeBytes());
        }
        await _waitParts();
        _throwIfFailed();
        await _api.completeMultipartUpload(bucket, key, _uploadId!, [
          for (final entry in _etags.entries) S3Part(number: entry.key, etag: entry.value),
        ]);
      }
      _completeDone();
    } catch (error, stack) {
      // `close()` упал — убирает за собой сам: после него `abort()` уже никто не
      // позовёт (`AbortableSink`).
      await _abortUpload();
      _completeDone();
      Error.throwWithStackTrace(error, stack);
    }
  }

  @override
  Future<void> abort() async {
    if (_finished && _done.isCompleted) {
      return;
    }
    _finished = true;
    await _subscription?.cancel();
    for (final abort in [..._aborts]) {
      abort.abort();
    }
    await _waitParts();
    await _abortUpload();
    _completeDone();
  }

  Future<void> _waitParts() async {
    while (_inFlight.isNotEmpty) {
      await Future.wait([..._inFlight]);
    }
  }

  void _throwIfFailed() {
    final failure = _failure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, _failureStack ?? StackTrace.current);
    }
  }

  Future<void> _abortUpload() async {
    final starting = _starting;
    if (starting == null) {
      return;
    }
    try {
      final id = await starting;
      await _api.abortMultipartUpload(bucket, key, id);
    } catch (_) {
      // Загрузку не завели или отменить не дали: рассказывать нужно о первой
      // ошибке, а не об уборке.
    }
  }

  void _completeDone() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  /// Длина, если её знали заранее, — для проверок.
  int? get length => _length;

  /// Бросить, если путь к объекту не годится.
  static void checkKey(String key) {
    if (key.isEmpty) {
      throw FsError(key, FsErrorKind.invalidName);
    }
  }
}
