import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:path/path.dart' as p;

import 'ftp_api.dart';
import 'ftp_connection.dart';
import 'ftp_features.dart';
import 'ftp_listing.dart';
import 'ftp_reply.dart';

/// [FtpApi] поверх настоящего соединения.
///
/// Здесь и только здесь живёт знание о том, какими командами что делается.
/// Провайдер об этом не знает — и потому проверяется подставкой.
class FtpOverConnection implements FtpApi {
  FtpOverConnection(this._ftp, {Future<FtpConnection> Function()? reopen}) : _reopen = reopen;

  FtpConnection _ftp;

  /// Чем поднять соединение заново; null — нечем, и отказ уходит как есть.
  ///
  /// Оборванное соединение не всегда доходит до нас разрывом: бывает, что
  /// канал данных просто замолкает навсегда, и тогда управляющий канал уже
  /// не в порядке — хвоста передачи в нём не дождаться. Чинится это
  /// единственным честным способом: подключиться заново
  /// (`docs/spec/ftp.md`, §3.7).
  final Future<FtpConnection> Function()? _reopen;

  @override
  FtpFeatures get features => _ftp.features;

  /// Список каталога: `MLSD`, а не вышло — `LIST`.
  ///
  /// Откат живёт здесь, а не в решении «умеет ли сервер»: `FEAT` подсказывает,
  /// но врёт (`docs/spec/ftp.md`, §3.2). Что сервер `MLSD` не умеет, узнаём
  /// один раз и дальше не спрашиваем — иначе каждый каталог стоил бы лишнего
  /// обмена.
  /// Сколько раз повторить сорванную передачу.
  ///
  /// Обрыв канала данных на ровном месте — не наша ошибка и не ошибка сервера:
  /// тот же обмен минимальным клиентом, без единой нашей строки, срывается
  /// примерно раз на сорок (`docs/spec/ftp.md`, §3.7). Сервер при этом
  /// считает передачу состоявшейся и продолжает работать — значит правильный
  /// ответ на такой обрыв повторить, а не показывать человеку ошибку там, где
  /// её нет.
  static const int _attempts = 3;

  /// Повторяет работу, если она сорвалась обрывом канала.
  ///
  /// Только [FsErrorKind.io]: «не найдено» и «нет доступа» повтором не
  /// лечатся, и дёргать ими сервер незачем.
  Future<T> _retrying<T>(Future<T> Function() body) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await body();
      } on FsError catch (error) {
        if (error.kind != FsErrorKind.io || attempt >= _attempts) {
          rethrow;
        }
        if (_ftp.isClosed) {
          final reopen = _reopen;
          if (reopen == null) {
            rethrow;
          }
          // Соединение больше не в порядке — повторять в него бессмысленно.
          _ftp = await reopen();
          _machine = _ftp.features.machineListing;
        }
      }
    }
  }

  @override
  Future<List<FtpEntry>> listDirectory(String path) => _retrying(() => _listDirectory(path));

  Future<List<FtpEntry>> _listDirectory(String path) async {
    if (_machine) {
      try {
        final lines = await _ftp.listing('MLSD', path);
        return [
          for (final line in lines)
            if (FtpListing.parseMachine(line) case final entry?) entry,
        ];
      } on FsError catch (error) {
        if (error.kind != FsErrorKind.notSupported) {
          rethrow;
        }
        _machine = false;
      }
    }

    final lines = await _ftp.listing('LIST', path);
    return [
      for (final line in lines)
        if (FtpListing.parseText(line) case final entry?)
          if (entry.name != '.' && entry.name != '..') entry,
    ];
  }

  late bool _machine = _ftp.features.machineListing;

  /// Один объект.
  ///
  /// `MLST` там, где он есть; иначе — поиск в списке своего каталога.
  /// Настоящего `stat` у FTP нет вовсе.
  @override
  Future<FtpEntry?> stat(String path) async {
    if (path == '/' || path.isEmpty) {
      return const FtpEntry(name: '/', type: FileType.directory);
    }

    if (_machine) {
      final reply = await _ftp.command('MLST $path');
      if (reply.code == 250) {
        for (final line in reply.lines) {
          final entry = FtpListing.parseMachine(line.trim());
          if (entry != null) {
            // `MLST` называет объект полным путём — панели нужно имя.
            return FtpEntry(
              name: p.posix.basename(entry.name),
              type: entry.type,
              size: entry.size,
              mode: entry.mode,
              owner: entry.owner,
              group: entry.group,
              modified: entry.modified,
              linkTarget: entry.linkTarget,
              permissions: entry.permissions,
            );
          }
        }
      }
      if (reply.code == 550) {
        return null;
      }
    }

    final name = p.posix.basename(path);
    final List<FtpEntry> siblings;
    try {
      siblings = await listDirectory(p.posix.dirname(path));
    } on FsError {
      return null;
    }
    for (final entry in siblings) {
      if (entry.name == name) {
        return entry;
      }
    }
    return null;
  }

  /// Открытие чтения повторяется так же: обрыв случается чаще всего сразу,
  /// ещё до первого байта. Уже начатый поток повторить нельзя — там за докачку
  /// отвечает движок, у которого для этого есть `canSeek`.
  @override
  Future<Stream<List<int>>> openRead(String path, {int offset = 0}) =>
      _retrying(() => _ftp.retrieve(path, offset: offset));

  @override
  Future<StreamSink<List<int>>> openWrite(String path) async {
    final sink = _FtpUploadSink(path);
    // Загрузка начинается сразу и идёт, пока в приёмник кладут байты: своего
    // буфера у неё нет, обратное давление настоящее.
    sink.attach(_ftp.store(path, sink.stream));
    return sink;
  }

  @override
  Future<void> makeDirectory(String path) async => _done(await _ftp.command('MKD $path'), path);

  @override
  Future<void> removeFile(String path) async => _done(await _ftp.command('DELE $path'), path);

  @override
  Future<void> removeDirectory(String path) async => _done(await _ftp.command('RMD $path'), path);

  @override
  Future<void> rename(String from, String to) async {
    final first = await _ftp.command('RNFR $from');
    if (first.code != 350) {
      throw FtpConnection.errorFor(from, first, writing: true);
    }
    _done(await _ftp.command('RNTO $to'), to);
  }

  /// Отказ на пишущей команде — всегда «не разрешено», а не «не найдено»:
  /// один код `550` значит и то и другое, и решает род команды
  /// (`docs/spec/ftp.md`, §3.4).
  static void _done(FtpReply reply, String path) {
    if (!reply.isPositive) {
      throw FtpConnection.errorFor(path, reply, writing: true);
    }
  }

  @override
  Future<void> close() => _ftp.close();
}

/// Приёмник байтов поверх идущей загрузки.
///
/// Своего буфера нет нарочно: байты уходят в сокет по мере поступления, и
/// обратное давление настоящее — движок не читает источник быстрее, чем сервер
/// принимает.
class _FtpUploadSink implements StreamSink<List<int>> {
  _FtpUploadSink(this._path);

  final String _path;
  final StreamController<List<int>> _out = StreamController<List<int>>();
  final Completer<void> _done = Completer<void>();

  Stream<List<int>> get stream => _out.stream;

  /// Связывает приёмник с загрузкой: её итог и есть [done].
  void attach(Future<void> upload) {
    upload.then(
      (_) {
        if (!_done.isCompleted) {
          _done.complete();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_done.isCompleted) {
          _done.completeError(error, stack);
        }
      },
    );
  }

  @override
  void add(List<int> data) {
    if (_out.isClosed) {
      throw StateError('Приёмник уже закрыт: $_path');
    }
    _out.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _out.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _out.addStream(stream);

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (!_out.isClosed) {
      await _out.close();
    }
    return _done.future;
  }
}
