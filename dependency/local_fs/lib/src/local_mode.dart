import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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

  /// Назначает режим; false — не вышло.
  ///
  /// Не бросает: единственный, кто это зовёт, — сохранение файла, и уронить
  /// уже записанное из-за неудавшегося `chmod` было бы хуже, чем оставить файл
  /// с правами по умолчанию.
  bool apply(String path, int mode) {
    final native = path.toNativeUtf8();
    try {
      return _chmod(native, mode) == 0;
    } finally {
      calloc.free(native);
    }
  }
}

typedef _ChmodNative = Int32 Function(Pointer<Utf8> path, Uint16 mode);
typedef _ChmodDart = int Function(Pointer<Utf8> path, int mode);
