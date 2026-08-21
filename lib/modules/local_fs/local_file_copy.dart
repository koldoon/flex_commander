import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'package:fc_api/fc_api.dart';

import 'local_listing.dart';

/// Константы `/usr/include/copyfile.h`.
///
/// Сверить их в работающем приложении не с чем: ошибка здесь не бросает
/// исключение, а роняет процесс. Поэтому они проверяются тестом —
/// `test/model/local_file_copy_test.dart` сличает их с заголовком SDK.
const int copyfileAll = 15; // COPYFILE_ACL | COPYFILE_STAT | COPYFILE_XATTR | COPYFILE_DATA
const int copyfileStateStatusCb = 6; // COPYFILE_STATE_STATUS_CB
const int copyfileStateCopied = 8; // COPYFILE_STATE_COPIED
const int copyfileCopyData = 4; // COPYFILE_COPY_DATA
const int copyfileFinish = 2; // COPYFILE_FINISH
const int copyfileProgress = 4; // COPYFILE_PROGRESS
const int copyfileContinue = 0; // COPYFILE_CONTINUE
const int copyfileQuit = 2; // COPYFILE_QUIT

/// `ECANCELED` — им `copyfile` отвечает на `COPYFILE_QUIT`.
const int _eCanceled = 89;

/// Как часто байты уходят наружу.
///
/// `copyfile` зовёт колбэк на каждый блок — это десятки тысяч сообщений в
/// секунду на быстром диске, а окно всё равно перерисовывается не чаще, чем раз
/// в 50 мс. Прореживание по обеим меркам сразу: мелкий файл не молчит до конца,
/// крупный не заваливает главный изолят.
const int _minInterval = 50;
const int _minChunk = 512 * 1024;

typedef _CopyfileNative = Int32 Function(Pointer<Utf8> from, Pointer<Utf8> to, Pointer<Void> state, Uint32 flags);
typedef _CopyfileDart = int Function(Pointer<Utf8> from, Pointer<Utf8> to, Pointer<Void> state, int flags);

typedef _StateAllocNative = Pointer<Void> Function();

typedef _StateFreeNative = Int32 Function(Pointer<Void> state);
typedef _StateFreeDart = int Function(Pointer<Void> state);

typedef _StateSetNative = Int32 Function(Pointer<Void> state, Uint32 flag, Pointer<Void> value);
typedef _StateSetDart = int Function(Pointer<Void> state, int flag, Pointer<Void> value);

typedef _StateGetNative = Int32 Function(Pointer<Void> state, Uint32 flag, Pointer<Void> value);
typedef _StateGetDart = int Function(Pointer<Void> state, int flag, Pointer<Void> value);

typedef _ErrnoNative = Pointer<Int32> Function();

typedef _StrErrorNative = Pointer<Utf8> Function(Int32 code);
typedef _StrErrorDart = Pointer<Utf8> Function(int code);

/// Колбэк `copyfile_callback_t`: что, на каком шаге, состояние, откуда, куда,
/// свои данные. Ответ — `COPYFILE_CONTINUE` или `COPYFILE_QUIT`.
typedef _StatusCallbackNative =
    Int32 Function(
      Int32 what,
      Int32 stage,
      Pointer<Void> state,
      Pointer<Utf8> from,
      Pointer<Utf8> to,
      Pointer<Void> context,
    );

/// Символы libSystem, разысканные один раз на изолят.
///
/// Берутся у [DynamicLibrary.process]: libSystem загружена всегда, и
/// доустанавливать ничего не нужно. Не нашлись — [instance] отдаёт null, и
/// звать копию остаётся старым способом.
class _Copyfile {
  _Copyfile._(this.copyfile, this.stateAlloc, this.stateFree, this.stateSet, this.stateGet, this.errno, this.strerror);

  final _CopyfileDart copyfile;
  final Pointer<Void> Function() stateAlloc;
  final _StateFreeDart stateFree;
  final _StateSetDart stateSet;
  final _StateGetDart stateGet;
  final Pointer<Int32> Function() errno;
  final _StrErrorDart strerror;

  static bool _looked = false;
  static _Copyfile? _found;

  /// Символы или null, если их нет. Статика здесь на изолят, а не на процесс, —
  /// и это правильно: искать их всё равно нужно в том изоляте, который зовёт.
  static _Copyfile? get instance {
    if (_looked) {
      return _found;
    }
    _looked = true;
    if (!Platform.isMacOS) {
      // `copyfile(3)` — только macOS. Остальным остаётся `File.copy`.
      return null;
    }
    try {
      final process = DynamicLibrary.process();
      _found = _Copyfile._(
        process.lookupFunction<_CopyfileNative, _CopyfileDart>('copyfile'),
        process.lookupFunction<_StateAllocNative, Pointer<Void> Function()>('copyfile_state_alloc'),
        process.lookupFunction<_StateFreeNative, _StateFreeDart>('copyfile_state_free'),
        process.lookupFunction<_StateSetNative, _StateSetDart>('copyfile_state_set'),
        process.lookupFunction<_StateGetNative, _StateGetDart>('copyfile_state_get'),
        process.lookupFunction<_ErrnoNative, Pointer<Int32> Function()>('__error'),
        process.lookupFunction<_StrErrorNative, _StrErrorDart>('strerror'),
      );
    } on ArgumentError {
      // Символа нет: не повод отказываться копировать вовсе.
      _found = null;
    }
    return _found;
  }
}

/// Есть ли у системы копия с ходом работы.
///
/// false — остаётся `File.copy`: тот же результат, только рассказать о себе он
/// не может.
bool get systemFileCopyAvailable => _Copyfile.instance != null;

/// Копия файла средствами macOS `copyfile(3)` — с ходом по байтам и отменой.
///
/// `File.copy` — один системный вызов, который отдаёт управление только целиком
/// скопированным файлом: на четырёх гигабайтах полоса стоит на нуле пять минут,
/// а прервать работу негде. `copyfile` о том же самом рассказывает по ходу дела
/// (`COPYFILE_STATE_STATUS_CB`) и сохраняет ровно то же, что и `File.copy`:
/// дату, права, xattr, ACL.
///
/// Флаги — `COPYFILE_ALL` без `COPYFILE_CLONE`: клон на APFS был бы мгновенным,
/// но колбэк данных при нём не приходит ни разу, то есть ровно та работа, ради
/// которой всё затевается, на самом частом случае и пропала бы.
///
/// [onBytes] зовётся в текущем изоляте приростом байт; false из него бросает
/// копию (`COPYFILE_QUIT`) на ближайшем куске и даёт [OperationCanceled].
/// Ошибка `copyfile` приходит [FsError] по `errno`.
///
/// Сам вызов уходит в отдельный изолят: `copyfile` синхронный, и на четырёх
/// гигабайтах он заморозил бы интерфейс. Тот же приём уже применён к чтению
/// каталога ([readDirectory]).
///
/// Звать можно только там, где [systemFileCopyAvailable]; без символов
/// копировать нечем.
Future<void> copyFileWithProgress(String source, String target, bool Function(int bytes) onBytes) async {
  if (!systemFileCopyAvailable) {
    throw StateError('copyfile(3) не найден: копировать нужно через File.copy');
  }

  // Отмена внутрь изолята: он стоит в нативном вызове и сообщений не читает,
  // поэтому не порт, а флаг в нативной памяти. Адрес переезжает границу
  // обычным числом.
  final cancel = calloc<Int32>();
  final port = ReceivePort();

  var reported = 0;
  var canceled = false;

  port.listen((message) {
    if (message is! int) {
      return;
    }
    reported += message;
    if (!onBytes(message)) {
      canceled = true;
      cancel.value = 1;
    }
  });

  final address = cancel.address;
  final sink = port.sendPort;
  try {
    final (failed, code, copied) = await _runCopy(source, target, sink, address);

    if (failed) {
      // Недописанное убирает движок: он же знает, что и под каким именем
      // писалось.
      if (canceled || code == _eCanceled) {
        throw const OperationCanceled();
      }
      throw _errorOf(source, code);
    }

    // Остаток: последние куски могли не пройти прореживание, а сумма должна
    // сойтись с размером файла. Порт закрывается до этого — иначе сообщение,
    // ещё стоящее в очереди, посчиталось бы дважды.
    final rest = copied - reported;
    port.close();
    if (rest > 0) {
      onBytes(rest);
    }
  } finally {
    port.close();
    calloc.free(cancel);
  }
}

/// Запуск изолята — отдельной функцией, а не замыканием на месте.
///
/// Замыкание уносит с собой **весь** контекст своей области видимости, а там
/// лежит `onBytes` движка — а вместе с ним и вся операция, которую через
/// границу изолята не передать. Здесь в области видимости только эти четыре
/// значения, и все они пересылаемые.
Future<(bool, int, int)> _runCopy(String source, String target, SendPort sink, int cancelAddress) {
  return Isolate.run(() => _copyBlocking(source, target, sink, cancelAddress));
}

/// Ошибка `errno` — в ту же [FsError], что и ошибки `dart:io`: разными путями
/// пришедшая одна и та же беда должна выглядеть одинаково.
FsError _errorOf(String path, int code) {
  final text = _Copyfile.instance?.strerror(code).toDartString() ?? 'errno $code';
  return fsErrorFrom(path, FileSystemException('Cannot copy the file', path, OSError(text, code)));
}

/// Сама копия — **блокирующим** вызовом в своём изоляте.
///
/// Отдаёт три числа: сорвалась ли работа, `errno` и сколько байт легло в
/// приёмник. Байты по ходу дела идут в [sink], а отмена приходит флагом по
/// адресу [cancelAddress].
(bool, int, int) _copyBlocking(String source, String target, SendPort sink, int cancelAddress) {
  final lib = _Copyfile.instance!;
  final cancel = Pointer<Int32>.fromAddress(cancelAddress);

  final from = source.toNativeUtf8();
  final to = target.toNativeUtf8();
  final copied = calloc<Int64>();
  final state = lib.stateAlloc();

  var reported = 0;
  var lastSent = 0;
  final watch = Stopwatch()..start();

  /// `copyfile` зовёт это на каждый блок — на том же потоке, который его
  /// вызвал, то есть на потоке изолята. Поэтому и `isolateLocal`: асинхронный
  /// `listener` здесь не нужен и не годится — ответ `copyfile` ждёт сразу.
  int onStatus(
    int what,
    int stage,
    Pointer<Void> current,
    Pointer<Utf8> src,
    Pointer<Utf8> dst,
    Pointer<Void> context,
  ) {
    if (cancel.value != 0) {
      // Работу бросают, а не приостанавливают: `copyfile` середину не помнит.
      return copyfileQuit;
    }
    if (what != copyfileCopyData || (stage != copyfileProgress && stage != copyfileFinish)) {
      return copyfileContinue;
    }
    if (lib.stateGet(current, copyfileStateCopied, copied.cast()) != 0) {
      return copyfileContinue;
    }

    final delta = copied.value - reported;
    if (delta <= 0) {
      return copyfileContinue;
    }
    // Конец файла отправляется всегда: на нём сумма и сходится с размером.
    if (stage == copyfileProgress && delta < _minChunk && watch.elapsedMilliseconds - lastSent < _minInterval) {
      return copyfileContinue;
    }

    reported = copied.value;
    lastSent = watch.elapsedMilliseconds;
    sink.send(delta);
    return copyfileContinue;
  }

  // Бросок из колбэка ушёл бы в нативный код, где его некому ловить: любой
  // сбой здесь значит «работу бросить».
  final callback = NativeCallable<_StatusCallbackNative>.isolateLocal(onStatus, exceptionalReturn: copyfileQuit);
  try {
    lib.stateSet(state, copyfileStateStatusCb, callback.nativeFunction.cast());
    if (lib.copyfile(from, to, state, copyfileAll) < 0) {
      return (true, lib.errno().value, reported);
    }

    // Сколько всего легло в приёмник: колбэк мог не застать последний блок.
    copied.value = 0;
    lib.stateGet(state, copyfileStateCopied, copied.cast());
    return (false, 0, copied.value > reported ? copied.value : reported);
  } finally {
    callback.close();
    lib.stateFree(state);
    calloc.free(copied);
    calloc.free(from);
    calloc.free(to);
  }
}
