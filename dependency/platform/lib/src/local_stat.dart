import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Числа владельца и группы — `stat(2)`.
///
/// В `dart:io` их нет: `FileStat` показывает вид, размер, режим и три даты, а
/// `st_uid` и `st_gid` не показывает вовсе. Всё остальное берётся оттуда —
/// сюда ходят только за этими двумя числами.
///
/// **Только macOS.** Раскладка `struct stat` у систем разная — у Linux одни
/// только первые поля другого размера, — а ошибка в ней не отказывает, а тихо
/// отдаёт чужие байты как числа владельца. Раскладка проверяется тестом против
/// `stat -f`, и такую проверку надо писать под каждую систему отдельно.
class LocalStat {
  const LocalStat._(this._stat);

  static LocalStat? _instance;
  static bool _looked = false;

  /// null — на этой платформе чисел владельца нам не достать.
  static LocalStat? get instance {
    if (_looked) {
      return _instance;
    }
    _looked = true;
    if (!Platform.isMacOS) {
      return null;
    }
    final process = DynamicLibrary.process();
    // Порядок важен. На x86_64 `stat` — это **старая** версия вызова, с
    // 32-битным номером узла и другой раскладкой полей за ним; шестидесяти-
    // четырёхбитная называется `stat$INODE64`. На arm64 старой нет вовсе, и
    // `stat` уже правильный. Спросив сперва про длинное имя, мы получаем
    // верную раскладку на обеих машинах.
    for (final name in const ['stat\$INODE64', 'stat']) {
      try {
        return _instance = LocalStat._(process.lookupFunction<_StatNative, _StatDart>(name));
      } on ArgumentError {
        continue;
      }
    }
    return null;
  }

  final _StatDart _stat;

  /// Всё, что нужно строке списка: режим, размер, времена и числа владельца.
  ///
  /// Одним вызовом, а не двумя: `dart:io` зовёт `stat(2)` ради `FileStat`, но
  /// чисел владельца оттуда не отдаёт — они в структуре есть, а в `FileStat`
  /// их нет. Свой вызов приносит и то и другое разом, и системных вызовов
  /// остаётся ровно столько же (`docs/spec/owner-columns.md`, §3).
  ///
  /// Время — в секундах эпохи, как его и хранит система. Наносекунды рядом с
  /// ними мы не читаем: в списке их всё равно не показывают.
  LocalStatInfo? readOf(String path) {
    final native = path.toNativeUtf8();
    final buffer = calloc<Uint8>(256);
    try {
      if (_stat(native, buffer.cast()) != 0) {
        return null;
      }
      final stat = buffer.cast<_Stat>().ref;
      return LocalStatInfo(
        mode: stat.mode,
        uid: stat.uid,
        gid: stat.gid,
        size: stat.size,
        accessed: _timeOf(stat.accessedSeconds),
        modified: _timeOf(stat.modifiedSeconds),
        changed: _timeOf(stat.changedSeconds),
      );
    } finally {
      calloc.free(buffer);
      calloc.free(native);
    }
  }

  static DateTime _timeOf(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  /// Числа владельца и группы; null — объекта нет или спросить не вышло.
  ({int uid, int gid})? ownerOf(String path) {
    final native = path.toNativeUtf8();
    // С запасом и нулями: настоящая `struct stat` — 144 байта, а читаем мы из
    // неё первые двадцать четыре. Запас здесь не роскошь, а единственное, что
    // отделяет ошибку в раскладке от порчи чужой памяти.
    final buffer = calloc<Uint8>(256);
    try {
      if (_stat(native, buffer.cast()) != 0) {
        return null;
      }
      final stat = buffer.cast<_Stat>().ref;
      return (uid: stat.uid, gid: stat.gid);
    } finally {
      calloc.free(buffer);
      calloc.free(native);
    }
  }
}

/// Начало `struct stat` — ровно до нужных полей и ни байтом дальше.
///
/// Дальше идут три `timespec`, размер и блоки; они приходят из `FileStat`, и
/// описывать их здесь значило бы завести второй источник тех же дат.
final class _Stat extends Struct {
  @Int32()
  external int device;

  @Uint16()
  external int mode;

  @Uint16()
  external int links;

  @Uint64()
  external int inode;

  @Uint32()
  external int uid;

  @Uint32()
  external int gid;

  /// `st_rdev` и выравнивание за ним: сами по себе не нужны, но без них
  /// поехали бы все поля дальше — структура читается по смещениям.
  @Int32()
  external int rdev;

  // ignore: unused_field
  @Int32()
  external int padding;

  @Int64()
  external int accessedSeconds;

  @Int64()
  external int accessedNanoseconds;

  @Int64()
  external int modifiedSeconds;

  @Int64()
  external int modifiedNanoseconds;

  @Int64()
  external int changedSeconds;

  @Int64()
  external int changedNanoseconds;

  @Int64()
  external int bornSeconds;

  @Int64()
  external int bornNanoseconds;

  @Int64()
  external int size;
}

/// Что рассказала о файле система.
class LocalStatInfo {
  const LocalStatInfo({
    required this.mode,
    required this.uid,
    required this.gid,
    required this.size,
    required this.accessed,
    required this.modified,
    required this.changed,
  });

  final int mode;
  final int uid;
  final int gid;
  final int size;
  final DateTime accessed;
  final DateTime modified;

  /// Когда менялись сами атрибуты — то же, что `FileStat.changed`.
  final DateTime changed;
}

typedef _StatNative = Int32 Function(Pointer<Utf8> path, Pointer<_Stat> out);
typedef _StatDart = int Function(Pointer<Utf8> path, Pointer<_Stat> out);
