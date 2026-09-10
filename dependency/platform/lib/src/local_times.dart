import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:fc_api/fc_api.dart';

import 'system_errors.dart';

/// Назначение дат — `utimensat(2)`.
///
/// В `dart:io` половина этого есть: у `File` найдутся `setLastModified` и
/// `setLastAccessed`. Но только у файла — каталогу дату не поставить ничем, а
/// правка атрибутов каталогов нужна ровно так же. Плюс `utimensat` умеет то,
/// чего у обоих нет: **не трогать** одну из двух дат, оставив вторую как есть.
///
/// Соседний `utimes(2)` проще, но требует обе даты сразу: чтобы поменять одну,
/// пришлось бы прочитать вторую и записать обратно — а между чтением и записью
/// её мог поменять кто угодно.
class LocalTimes {
  const LocalTimes._(this._utimensat, this._omit, this._atFdCwd);

  static LocalTimes? _instance;
  static bool _looked = false;

  /// null — на этой платформе назначить даты нечем (Windows).
  static LocalTimes? get instance {
    if (_looked) {
      return _instance;
    }
    _looked = true;
    if (Platform.isWindows) {
      return null;
    }
    // Числа у одного и того же вызова разные, и подсмотреть их в работающем
    // приложении не с чего: `UTIME_OMIT` чужой системы просто поставит дату
    // в 1970 год, не сказав ни слова. Проверяются тестом по заголовкам SDK.
    final omit = Platform.isMacOS ? -2 : (1 << 30) - 2;
    final atFdCwd = Platform.isMacOS ? -2 : -100;
    return _instance = LocalTimes._(
      DynamicLibrary.process().lookupFunction<_UtimensatNative, _UtimensatDart>('utimensat'),
      omit,
      atFdCwd,
    );
  }

  final _UtimensatDart _utimensat;

  /// «Эту дату не трогать» — `UTIME_OMIT`.
  final int _omit;

  /// «Путь считать от текущего каталога» — `AT_FDCWD`.
  final int _atFdCwd;

  /// Назначает даты; null — не трогать эту. Не вышло — [FsError] по `errno`.
  ///
  /// Порядок в паре — тот же, что в системном вызове: сперва доступ, потом
  /// изменение.
  void apply(String path, {DateTime? modified, DateTime? accessed}) {
    if (modified == null && accessed == null) {
      return;
    }
    final native = path.toNativeUtf8();
    final times = calloc<_Timespec>(2);
    try {
      _fill(times[0], accessed);
      _fill(times[1], modified);
      // Флаг 0 — по ссылке идём, как и `chmod(2)`: правят обычно тот объект,
      // на который смотрят в панели, а смотрят на цель.
      if (_utimensat(_atFdCwd, native, times, 0) != 0) {
        throw fsErrorFromErrno(path, systemErrno, what: 'Cannot change the timestamps');
      }
    } finally {
      calloc.free(times);
      calloc.free(native);
    }
  }

  void _fill(_Timespec slot, DateTime? at) {
    if (at == null) {
      slot.seconds = 0;
      slot.nanoseconds = _omit;
      return;
    }
    final micros = at.microsecondsSinceEpoch;
    // Деление с округлением вниз, а не `~/`: до 1970 года тот отсекает к нулю,
    // и дата уезжала бы на секунду вперёд.
    final seconds = (micros / Duration.microsecondsPerSecond).floor();
    slot.seconds = seconds;
    slot.nanoseconds = (micros - seconds * Duration.microsecondsPerSecond) * 1000;
  }
}

/// `struct timespec`: секунды эпохи и наносекунды. Оба поля — машинное слово.
final class _Timespec extends Struct {
  @Int64()
  external int seconds;

  @Int64()
  external int nanoseconds;
}

typedef _UtimensatNative = Int32 Function(Int32 directory, Pointer<Utf8> path, Pointer<_Timespec> times, Int32 flags);
typedef _UtimensatDart = int Function(int directory, Pointer<Utf8> path, Pointer<_Timespec> times, int flags);
