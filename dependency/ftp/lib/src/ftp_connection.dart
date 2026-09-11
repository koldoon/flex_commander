import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';

import 'ftp_address.dart';
import 'ftp_features.dart';
import 'ftp_reply.dart';

/// Управляющее соединение с сервером: вход, команды, каналы данных.
///
/// **Одно соединение — одна работа.** У FTP управляющий канал один, и передача
/// его занимает: пока идёт `RETR`, спросить в него `SIZE` нельзя. Поэтому
/// команды выстраиваются в очередь, а чтение файла держит свою очередь до тех
/// пор, пока поток не дочитают или не бросят (`docs/spec/ftp.md`, §5).
class FtpConnection {
  FtpConnection._(this.target, this._control, {required this.encoding});

  /// Сколько ждать ответа на команду. Сервер, который молчит дольше, считается
  /// отвалившимся: висеть в панели без объяснений хуже, чем сказать об ошибке.
  static const Duration replyTimeout = Duration(seconds: 30);

  final FtpTarget target;

  /// Кодировка имён и команд. UTF-8, пока сервер не сказал иначе
  /// (`docs/spec/ftp.md`, §9).
  final Encoding encoding;

  Socket _control;

  /// Что сервер объявил в `FEAT`. До входа — «ничего не умеет».
  FtpFeatures features = FtpFeatures.none();

  /// Дочитанные ответы, до которых ещё не дошли руки.
  final Queue<FtpReply> _replies = Queue<FtpReply>();

  /// Кто ждёт следующего ответа.
  Completer<FtpReply>? _waiting;

  final FtpReplyReader _reader = FtpReplyReader();
  final List<int> _incoming = [];
  StreamSubscription<Uint8List>? _listener;

  /// Идёт смена сокета на защищённый: `done` от старого — не разрыв связи.
  bool _upgrading = false;

  /// Связь оборвалась: дальше все команды отказывают сразу, а не ждут таймаута.
  Object? _broken;

  /// Хвост очереди команд: следующая ждёт, пока закончится предыдущая.
  Future<void> _queue = Future<void>.value();

  bool get isClosed => _broken != null;

  /// Подключается и входит на сервер.
  ///
  /// [password] спрашивает тот, кто зовёт: секрет — не дело протокола.
  /// [onBadCertificate] решает судьбу неизвестного сертификата; null —
  /// принимать только проверяемые.
  static Future<FtpConnection> open(
    FtpTarget target, {
    required String password,
    Duration timeout = const Duration(seconds: 20),
    bool Function(X509Certificate certificate)? onBadCertificate,
  }) async {
    final Socket socket;
    try {
      socket = await Socket.connect(target.host, target.port, timeout: timeout);
    } on SocketException catch (error) {
      throw FsError(target.display, FsErrorKind.io, error);
    }

    final connection = FtpConnection._(target, socket, encoding: utf8);
    connection._attach(socket);
    try {
      // Приветствие бывает баннером в два десятка строк — разбор ответа это
      // умеет (`docs/spec/ftp.md`, §3.1).
      final hello = await connection._expect(await connection._read(), what: target.display);
      if (hello.code != 220) {
        throw FsError(target.display, FsErrorKind.io);
      }

      if (target.secure) {
        await connection._startTls(onBadCertificate);
      }
      await connection._login(password);
      await connection._settle();
      return connection;
    } on Object {
      await connection.close();
      rethrow;
    }
  }

  // --- вход и настройка сеанса ---

  Future<void> _startTls(bool Function(X509Certificate)? onBadCertificate) async {
    final auth = await _raw('AUTH TLS');
    if (!auth.isPositive) {
      // Сервер объявляет `AUTH TLS` в `FEAT` и отказывает на самой команде —
      // так делает живой сервер из разведки. Молча продолжать открытым текстом
      // нельзя: человек просил `ftps://` (`docs/spec/ftp.md`, §3.2).
      throw FsError(target.display, FsErrorKind.notSupported);
    }

    _upgrading = true;
    await _listener?.cancel();
    _listener = null;
    try {
      final secured = await SecureSocket.secure(
        _control,
        host: target.host,
        onBadCertificate: onBadCertificate == null ? null : (certificate) => onBadCertificate(certificate),
      );
      _control = secured;
      _attach(secured);
    } on HandshakeException catch (error) {
      throw FsError(target.display, FsErrorKind.permissionDenied, error);
    } finally {
      _upgrading = false;
    }

    // Без `PROT P` шифруется только управляющий канал, а данные идут
    // открытыми — то есть то, ради чего всё затевалось, не работает.
    await _expect(await _raw('PBSZ 0'), what: target.display);
    await _expect(await _raw('PROT P'), what: target.display);
    _protected = true;
  }

  /// Канал данных тоже шифруется.
  bool _protected = false;

  Future<void> _login(String password) async {
    final user = await _raw('USER ${target.user}');
    if (user.code == 230) {
      return;
    }
    if (user.code != 331 && user.code != 332) {
      throw FsError(target.display, FsErrorKind.permissionDenied);
    }
    // Пароль в журнал не попадает: команда печатается без довода.
    final pass = await _raw('PASS $password', secret: true);
    if (pass.code != 230 && pass.code != 202) {
      throw FsError(target.display, FsErrorKind.permissionDenied);
    }
  }

  /// То, что делается один раз после входа.
  Future<void> _settle() async {
    final feat = await _raw('FEAT');
    features = feat.code == 211 ? FtpFeatures(feat.lines.sublist(1, feat.lines.length - 1)) : FtpFeatures.none();

    if (features.utf8) {
      // Ответ не проверяем: сервер, объявивший UTF8 и отказавший на `OPTS`,
      // всё равно понимает имена как байты, а мы их так и шлём.
      await _raw('OPTS UTF8 ON');
    }

    // **Двоичный режим ставится сразу и держится весь сеанс.** В ASCII нет ни
    // размера, ни докачки: `550 SIZE not allowed in ASCII mode`,
    // `501 REST: Resuming transfers not allowed in ASCII mode`. Ловушка тем и
    // неприятна, что не видна: каталог покажется, просто без размеров
    // (`docs/spec/ftp.md`, §3.3).
    await _expect(await _raw('TYPE I'), what: target.display);
  }

  // --- команды ---

  /// Команда, дожидающаяся своей очереди.
  Future<FtpReply> command(String line, {bool secret = false}) => _enqueue(() => _raw(line, secret: secret));

  /// Команда без очереди — только изнутри уже занятой очереди.
  Future<FtpReply> _raw(String line, {bool secret = false}) async {
    _checkAlive();
    try {
      _control.add(encoding.encode('$line\r\n'));
      await _control.flush();
    } on Object catch (error) {
      _break(error);
      throw FsError(target.display, FsErrorKind.io, error);
    }
    return _read();
  }

  Future<T> _enqueue<T>(Future<T> Function() body) {
    final result = _queue.then((_) => body());
    // Очередь движется дальше и после неудачи: отказ одной команды не должен
    // запирать соединение навсегда.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<FtpReply> _read() {
    if (_replies.isNotEmpty) {
      return Future.value(_replies.removeFirst());
    }
    final broken = _broken;
    if (broken != null) {
      return Future.error(FsError(target.display, FsErrorKind.io, broken));
    }
    final waiter = Completer<FtpReply>();
    _waiting = waiter;
    return waiter.future.timeout(
      replyTimeout,
      onTimeout: () {
        _break(TimeoutException('Сервер молчит', replyTimeout));
        throw FsError(target.display, FsErrorKind.io);
      },
    );
  }

  /// Ответ должен быть положительным; иначе — ошибка на языке дерева.
  Future<FtpReply> _expect(FtpReply reply, {required String what, bool writing = false}) async {
    if (reply.isPositive) {
      return reply;
    }
    throw errorFor(what, reply, writing: writing);
  }

  /// Перевод отказа сервера в ошибку дерева.
  ///
  /// **Один код `550` значит и «не найдено», и «не разрешено»** — живой сервер
  /// отвечает им и на `MLSD /нет-такого`, и на `STOR` в чужой каталог. Текст
  /// разбирать нельзя: он на языке сервера и у каждого свой. Поэтому решает
  /// **род команды**: читающая — «не найдено», пишущая — «не разрешено»
  /// (`docs/spec/ftp.md`, §3.4).
  static FsError errorFor(String path, FtpReply reply, {required bool writing}) {
    final kind = switch (reply.code) {
      530 => FsErrorKind.permissionDenied,
      532 || 552 => FsErrorKind.permissionDenied,
      450 || 451 || 425 || 426 => FsErrorKind.io,
      501 || 500 || 502 || 504 => FsErrorKind.notSupported,
      553 => FsErrorKind.invalidName,
      550 => writing ? FsErrorKind.permissionDenied : FsErrorKind.notFound,
      _ => writing ? FsErrorKind.permissionDenied : FsErrorKind.io,
    };
    return FsError(path, kind);
  }

  // --- канал данных ---

  /// Пассивный режим: открывает канал и отдаёт сокет.
  ///
  /// `EPSV` первым: он не зависит от версии адреса и не ломается, когда сервер
  /// за NAT называет в `PASV` свой внутренний адрес. Хост берётся тот, к
  /// которому уже подключены, — названный сервером отправил бы нас не туда
  /// (`docs/spec/ftp.md`, §6).
  Future<Socket> _openData() async {
    int? port;
    if (features.extendedPassive || !_triedExtended) {
      _triedExtended = true;
      final epsv = await _raw('EPSV');
      port = _extendedPort(epsv);
    }
    if (port == null) {
      final pasv = await _raw('PASV');
      port = _passivePort(pasv);
      if (port == null) {
        throw FsError(target.display, FsErrorKind.notSupported);
      }
    }

    try {
      final socket = await Socket.connect(target.host, port, timeout: replyTimeout);
      if (!_protected) {
        return socket;
      }
      return await SecureSocket.secure(socket, host: target.host, onBadCertificate: (_) => true);
    } on SocketException catch (error) {
      throw FsError(target.display, FsErrorKind.io, error);
    }
  }

  bool _triedExtended = false;

  /// `229 Entering Extended Passive Mode (|||20870|)` — в ответе только порт.
  static int? _extendedPort(FtpReply reply) {
    if (reply.code != 229) {
      return null;
    }
    final match = RegExp(r'\(([!-~])\1\1(\d+)\1\)').firstMatch(reply.message);
    return match == null ? null : int.tryParse(match.group(2)!);
  }

  /// `227 Entering Passive Mode (192,168,0,1,81,134)` — адрес и две половины
  /// порта. Адрес отбрасываем нарочно (см. [_openData]).
  static int? _passivePort(FtpReply reply) {
    if (reply.code != 227) {
      return null;
    }
    final match = RegExp(
      r'(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)',
    ).firstMatch(reply.message);
    if (match == null) {
      return null;
    }
    final high = int.tryParse(match.group(5)!);
    final low = int.tryParse(match.group(6)!);
    if (high == null || low == null) {
      return null;
    }
    return high * 256 + low;
  }

  /// Список каталога строками: `MLSD` или `LIST`.
  Future<List<String>> listing(String command, String path) => _enqueue(() async {
    final data = await _openData();
    try {
      final start = await _raw('$command $path');
      if (!start.isAboutToTransfer) {
        throw errorFor(path, start, writing: false);
      }
      final bytes = <int>[];
      await for (final chunk in data) {
        bytes.addAll(chunk);
      }
      await _expect(await _read(), what: path);
      return LineSplitter.split(encoding.decode(bytes)).where((line) => line.isNotEmpty).toList();
    } finally {
      data.destroy();
    }
  });

  /// Чтение файла потоком.
  ///
  /// Очередь держится **до конца чтения**: пока идут байты, управляющий канал
  /// занят. Бросили поток на середине — очередь освобождается, а соединение
  /// приводится в порядок `ABOR`.
  Future<Stream<List<int>>> retrieve(String path, {int offset = 0}) {
    final ready = Completer<Stream<List<int>>>();
    final finished = Completer<void>();
    _enqueue(() async {
      Socket? opened;
      try {
        opened = await _openData();
        if (offset > 0) {
          final rest = await _raw('REST $offset');
          if (rest.code != 350) {
            throw errorFor(path, rest, writing: false);
          }
        }
        final start = await _raw('RETR $path');
        if (!start.isAboutToTransfer) {
          throw errorFor(path, start, writing: false);
        }
      } on Object catch (error, stack) {
        // Канал мог уже открыться: `REST` и `RETR` отказывают после него.
        opened?.destroy();
        if (!ready.isCompleted) {
          ready.completeError(error, stack);
        }
        return;
      }

      final socket = opened;
      final out = StreamController<List<int>>();
      var closed = false;
      Future<void> done(Object? error, StackTrace? stack) async {
        if (closed) {
          return;
        }
        closed = true;
        socket.destroy();
        if (error != null) {
          out.addError(error, stack);
        } else {
          try {
            await _expect(await _read(), what: path);
          } on Object catch (tail, tailStack) {
            out.addError(tail, tailStack);
          }
        }
        await out.close();
        finished.complete();
      }

      final subscription = socket.listen(
        out.add,
        onError: (Object error, StackTrace stack) => unawaited(done(error, stack)),
        onDone: () => unawaited(done(null, null)),
        cancelOnError: true,
      );
      out
        ..onPause = subscription.pause
        ..onResume = subscription.resume
        ..onCancel = () async {
          // Бросили на середине: сервер надо остановить, иначе он будет слать
          // байты в закрытый сокет, а следующая команда прочтёт его хвост.
          if (!closed) {
            closed = true;
            await subscription.cancel();
            socket.destroy();
            await _abort();
            finished.complete();
          }
        };

      ready.complete(out.stream);
      await finished.future;
    });
    return ready.future;
  }

  /// Запись файла потоком.
  Future<void> store(String path, Stream<List<int>> data, {bool append = false}) => _enqueue(() async {
    final socket = await _openData();
    var sent = false;
    try {
      final start = await _raw('${append ? 'APPE' : 'STOR'} $path');
      if (!start.isAboutToTransfer) {
        throw errorFor(path, start, writing: true);
      }
      await socket.addStream(data);
      await socket.flush();
      sent = true;
    } finally {
      await socket.close().catchError((_) {});
      socket.destroy();
    }
    if (sent) {
      await _expect(await _read(), what: path, writing: true);
    }
  });

  /// Прервать передачу, о которой сервер ещё не знает.
  Future<void> _abort() async {
    try {
      _control.add(encoding.encode('ABOR\r\n'));
      await _control.flush();
      // Ответов бывает два: `426` о брошенной передаче и `226` об `ABOR`.
      final first = await _read();
      if (first.code == 426) {
        await _read();
      }
    } on Object {
      // Прервать не вышло — соединение всё равно больше не в порядке.
      _break(const FtpAborted());
    }
  }

  // --- сокет ---

  void _attach(Socket socket) {
    _listener = socket.listen(
      _onBytes,
      onError: (Object error) => _break(error),
      onDone: () {
        if (!_upgrading) {
          _break(const SocketException('Сервер закрыл соединение'));
        }
      },
    );
  }

  void _onBytes(List<int> bytes) {
    _incoming.addAll(bytes);
    while (true) {
      final at = _incoming.indexOf(0x0a);
      if (at < 0) {
        return;
      }
      var end = at;
      if (end > 0 && _incoming[end - 1] == 0x0d) {
        end--;
      }
      final line = encoding.decode(_incoming.sublist(0, end));
      _incoming.removeRange(0, at + 1);

      final reply = _reader.add(line);
      if (reply != null) {
        _deliver(reply);
      }
    }
  }

  void _deliver(FtpReply reply) {
    final waiter = _waiting;
    if (waiter != null && !waiter.isCompleted) {
      _waiting = null;
      waiter.complete(reply);
      return;
    }
    // Ответ, которого никто не ждал: сервер сам сообщает, что закрывает
    // соединение (`421 Timeout`). Копим — следующая команда его и прочтёт.
    _replies.add(reply);
  }

  void _break(Object error) {
    if (_broken != null) {
      return;
    }
    _broken = error;
    final waiter = _waiting;
    _waiting = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(FsError(target.display, FsErrorKind.io, error));
    }
  }

  void _checkAlive() {
    final broken = _broken;
    if (broken != null) {
      throw FsError(target.display, FsErrorKind.io, broken);
    }
  }

  Future<void> close() async {
    if (_broken == null) {
      try {
        await _raw('QUIT').timeout(const Duration(seconds: 3));
      } on Object {
        // Прощаться необязательно: соединение всё равно закрываем.
      }
    }
    _break(const FtpClosed());
    await _listener?.cancel();
    _listener = null;
    _control.destroy();
  }
}

/// Передача брошена по просьбе.
class FtpAborted implements Exception {
  const FtpAborted();

  @override
  String toString() => 'Передача прервана';
}

/// Соединение закрыто нами.
class FtpClosed implements Exception {
  const FtpClosed();

  @override
  String toString() => 'Соединение закрыто';
}
