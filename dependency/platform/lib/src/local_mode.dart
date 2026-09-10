import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:fc_api/fc_api.dart';

import 'system_errors.dart';

/// Назначение режима доступа — `chmod(2)`.
///
/// Через FFI, потому что в `dart:io` этого нет вовсе: файл можно прочитать,
/// записать, переименовать и удалить, а права у него — только прочитать. Библиотека
/// берётся у [DynamicLibrary.process]: libSystem загружена всегда, как и у
/// `copyfile(3)` по соседству.
class LocalMode {
  const LocalMode._(this._chmod);

  static LocalMode? _instance;

  /// null — на этой платформе назначить режим нечем (Windows).
  static LocalMode? get instance {
    if (Platform.isWindows) {
      return null;
    }
    return _instance ??= LocalMode._(DynamicLibrary.process().lookupFunction<_ChmodNative, _ChmodDart>('chmod'));
  }

  final _ChmodDart _chmod;

  /// Назначает режим; не вышло — [FsError] по `errno`.
  ///
  /// **Бросает**, в отличие от прежней редакции. Молчать здесь больше нельзя:
  /// режим теперь назначают и по прямой просьбе человека, а «нажал Apply, и
  /// ничего не произошло» — это ровно то, чего приложение не делает. Тому
  /// единственному месту, которому отказ безразличен, — переносу режима при
  /// записи файла (`NodeAttributesEditor.carryMode`), — молчать проще самому:
  /// оно и знает, почему ему можно.
  void apply(String path, int mode) {
    final native = path.toNativeUtf8();
    try {
      if (_chmod(native, mode) != 0) {
        throw fsErrorFromErrno(path, systemErrno, what: 'Cannot change the mode');
      }
    } finally {
      calloc.free(native);
    }
  }
}

typedef _ChmodNative = Int32 Function(Pointer<Utf8> path, Uint16 mode);
typedef _ChmodDart = int Function(Pointer<Utf8> path, int mode);
