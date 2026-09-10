import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:fc_api/fc_api.dart';

/// Переводит ошибку `dart:io` в ошибку дерева.
///
/// Платформенное по существу: коды у систем разные, и таблица их соответствий —
/// ровно то, что придётся дописывать, когда дойдут руки до третьей.
FsError fsErrorFrom(String path, FileSystemException error) {
  final code = error.osError?.errorCode;
  final kind =
      Platform.isWindows
          ? switch (code) {
            2 || 3 => FsErrorKind.notFound, // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND
            5 => FsErrorKind.permissionDenied, // ERROR_ACCESS_DENIED
            267 => FsErrorKind.notADirectory, // ERROR_DIRECTORY
            _ => FsErrorKind.io,
          }
          : switch (code) {
            // EPERM и EACCES — оба про «не пустили», и разница между ними не
            // та, о которой стоит рассказывать человеку: первый значит «этого
            // не может никто, кроме суперпользователя» (смена владельца),
            // второй — «прав на этот объект не хватило».
            1 || 13 => FsErrorKind.permissionDenied, // EPERM, EACCES
            2 => FsErrorKind.notFound, // ENOENT
            20 => FsErrorKind.notADirectory, // ENOTDIR
            _ => FsErrorKind.io,
          };
  return FsError(path, kind, error);
}

/// Ошибка системного вызова по `errno` — в ту же [FsError], что и ошибки
/// `dart:io`.
///
/// Разными путями пришедшая одна и та же беда должна выглядеть одинаково:
/// «Permission denied» из `chmod(2)` и из `File.writeAsString` — это одно и то
/// же для того, кто читает окно.
///
/// [what] уходит только в журнал: наружу из [FsError] едет её собственный
/// [FsError.message], собранный по виду ошибки.
FsError fsErrorFromErrno(String path, int code, {String what = 'System call failed'}) {
  final text = _Errno.instance?.describe(code) ?? 'errno $code';
  return fsErrorFrom(path, FileSystemException(what, path, OSError(text, code)));
}

/// `errno` последнего системного вызова; 0 — узнать не у кого (Windows).
int get systemErrno => _Errno.instance?.value ?? 0;

/// `errno` и `strerror(3)` — то немногое, что нужно всем вызовам через FFI.
///
/// Отдельно от каждого из них: `errno` — это не переменная, а вызов
/// (`__error()` на macOS, `__errno_location()` на Linux), и разыскивать его
/// заново в каждом соседнем файле незачем.
class _Errno {
  _Errno._(this._location, this._strerror);

  static _Errno? _instance;
  static bool _looked = false;

  /// null — на этой платформе `errno` нам недоступен.
  static _Errno? get instance {
    if (_looked) {
      return _instance;
    }
    _looked = true;
    if (Platform.isWindows) {
      return null;
    }
    final process = DynamicLibrary.process();
    // Имя у одного и того же разное: `__error` на macOS, `__errno_location`
    // на Linux. Третья система принесёт третье имя — и это ровно тот случай,
    // ради которого платформенное живёт здесь, а не в провайдере.
    final name = Platform.isMacOS ? '__error' : '__errno_location';
    return _instance = _Errno._(
      process.lookupFunction<_ErrnoNative, Pointer<Int32> Function()>(name),
      process.lookupFunction<_StrErrorNative, _StrErrorDart>('strerror'),
    );
  }

  final Pointer<Int32> Function() _location;
  final _StrErrorDart _strerror;

  int get value => _location().value;

  String describe(int code) => _strerror(code).toDartString();
}

typedef _ErrnoNative = Pointer<Int32> Function();

typedef _StrErrorNative = Pointer<Utf8> Function(Int32 code);
typedef _StrErrorDart = Pointer<Utf8> Function(int code);
