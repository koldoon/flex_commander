import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:fc_api/fc_api.dart';

import 'system_errors.dart';

/// Смена владельца и группы — `chown(2)`.
///
/// В `dart:io` нет ни этого, ни самих чисел владельца: `FileStat` их не
/// показывает вовсе.
///
/// Получиться это обычно **не должно**: сменить владельца может только
/// суперпользователь, а группу — только на ту, в которой состоишь. Отказ здесь
/// — обычное дело, и он выходит наружу [FsError] как есть: приложение не
/// делает вид, что сработало.
class LocalOwner {
  const LocalOwner._(this._chown);

  static LocalOwner? _instance;

  /// null — на этой платформе владельца нет вовсе (Windows).
  static LocalOwner? get instance {
    if (Platform.isWindows) {
      return null;
    }
    return _instance ??= LocalOwner._(DynamicLibrary.process().lookupFunction<_ChownNative, _ChownDart>('chown'));
  }

  final _ChownDart _chown;

  /// `chown(2)` с «не трогать» вместо пропущенного.
  ///
  /// «Не трогать» — это `-1`, а в беззнаковом `uid_t` то же самое число
  /// записывается как `0xFFFFFFFF`. Так задумано в самом вызове, и другого
  /// способа поменять только группу у него нет.
  void apply(String path, {int? uid, int? gid}) {
    if (uid == null && gid == null) {
      return;
    }
    const keep = 0xFFFFFFFF;
    final native = path.toNativeUtf8();
    try {
      if (_chown(native, uid ?? keep, gid ?? keep) != 0) {
        throw fsErrorFromErrno(path, systemErrno, what: 'Cannot change the owner');
      }
    } finally {
      calloc.free(native);
    }
  }
}

typedef _ChownNative = Int32 Function(Pointer<Utf8> path, Uint32 uid, Uint32 gid);
typedef _ChownDart = int Function(Pointer<Utf8> path, int uid, int gid);
