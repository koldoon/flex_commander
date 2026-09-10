import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'system_errors.dart';

/// Расширенные атрибуты файла — `listxattr(2)` и соседи.
///
/// На macOS ими помечено всё подряд: карантин Gatekeeper
/// (`com.apple.quarantine`), из-за которого скачанный файл встречают вопросом;
/// цветные метки Finder; `com.apple.metadata:*`. Менеджер, который их не
/// показывает, рассказывает о файле неправду.
///
/// **Только macOS.** Вызовы называются одинаково, но подписи у них разные: у
/// macOS есть лишние `position` и `options`, у Linux вместо них `flags` — и
/// только у `setxattr`. Писать вслепую вторую пару нельзя: ошибка в подписи
/// FFI не бросает исключение, а роняет процесс. Linux получит своё вместе с
/// портированием, а до тех пор умения там просто нет — как у системных значков
/// (роадмап, Б7).
class LocalXattr {
  const LocalXattr._(this._list, this._get, this._set, this._remove);

  static LocalXattr? _instance;
  static bool _looked = false;

  /// `ENOATTR` — «такого атрибута у файла нет». Не ошибка, а ответ.
  static const int _noAttribute = 93;

  /// null — на этой платформе расширенных атрибутов для нас нет.
  static LocalXattr? get instance {
    if (_looked) {
      return _instance;
    }
    _looked = true;
    if (!Platform.isMacOS) {
      return null;
    }
    final process = DynamicLibrary.process();
    return _instance = LocalXattr._(
      process.lookupFunction<_ListNative, _ListDart>('listxattr'),
      process.lookupFunction<_GetNative, _GetDart>('getxattr'),
      process.lookupFunction<_SetNative, _SetDart>('setxattr'),
      process.lookupFunction<_RemoveNative, _RemoveDart>('removexattr'),
    );
  }

  final _ListDart _list;
  final _GetDart _get;
  final _SetDart _set;
  final _RemoveDart _remove;

  /// Имена всех расширенных атрибутов объекта; пусто — их нет.
  ///
  /// Спрашивается дважды: первый раз с нулевым размером — узнать, сколько
  /// места нужно, второй — за самими именами. Так устроен сам вызов, и
  /// угадывать размер наперёд нечем.
  List<String> names(String path) {
    final native = path.toNativeUtf8();
    try {
      final size = _list(native, nullptr, 0, 0);
      if (size < 0) {
        throw fsErrorFromErrno(path, systemErrno, what: 'Cannot list extended attributes');
      }
      if (size == 0) {
        return const [];
      }
      final buffer = calloc<Uint8>(size);
      try {
        final written = _list(native, buffer.cast(), size, 0);
        if (written < 0) {
          throw fsErrorFromErrno(path, systemErrno, what: 'Cannot list extended attributes');
        }
        return _split(buffer.asTypedList(written));
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(native);
    }
  }

  /// Значение атрибута байтами; null — такого атрибута нет.
  Uint8List? read(String path, String name) {
    final nativePath = path.toNativeUtf8();
    final nativeName = name.toNativeUtf8();
    try {
      final size = _get(nativePath, nativeName, nullptr, 0, 0, 0);
      if (size < 0) {
        if (systemErrno == _noAttribute) {
          return null;
        }
        throw fsErrorFromErrno(path, systemErrno, what: 'Cannot read an extended attribute');
      }
      if (size == 0) {
        // Пустое значение — законное: атрибут есть, байтов у него нет.
        return Uint8List(0);
      }
      final buffer = calloc<Uint8>(size);
      try {
        final written = _get(nativePath, nativeName, buffer.cast(), size, 0, 0);
        if (written < 0) {
          throw fsErrorFromErrno(path, systemErrno, what: 'Cannot read an extended attribute');
        }
        // Копия, а не вид на чужую память: буфер сейчас освободится.
        return Uint8List.fromList(buffer.asTypedList(written));
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(nativeName);
      calloc.free(nativePath);
    }
  }

  /// Кладёт значение; атрибут заводится, если его не было.
  void write(String path, String name, List<int> value) {
    final nativePath = path.toNativeUtf8();
    final nativeName = name.toNativeUtf8();
    final buffer = calloc<Uint8>(value.isEmpty ? 1 : value.length);
    try {
      buffer.asTypedList(value.length).setAll(0, value);
      if (_set(nativePath, nativeName, buffer.cast(), value.length, 0, 0) != 0) {
        throw fsErrorFromErrno(path, systemErrno, what: 'Cannot write an extended attribute');
      }
    } finally {
      calloc.free(buffer);
      calloc.free(nativeName);
      calloc.free(nativePath);
    }
  }

  /// Убирает атрибут. Его уже нет — молчим: просили именно этого.
  void erase(String path, String name) {
    final nativePath = path.toNativeUtf8();
    final nativeName = name.toNativeUtf8();
    try {
      if (_remove(nativePath, nativeName, 0) != 0 && systemErrno != _noAttribute) {
        throw fsErrorFromErrno(path, systemErrno, what: 'Cannot remove an extended attribute');
      }
    } finally {
      calloc.free(nativeName);
      calloc.free(nativePath);
    }
  }

  /// Имена лежат в одном буфере подряд, каждое закрыто нулём.
  static List<String> _split(Uint8List buffer) {
    final names = <String>[];
    var start = 0;
    for (var i = 0; i < buffer.length; i++) {
      if (buffer[i] != 0) {
        continue;
      }
      if (i > start) {
        names.add(utf8.decode(buffer.sublist(start, i), allowMalformed: true));
      }
      start = i + 1;
    }
    return names;
  }
}

typedef _ListNative = IntPtr Function(Pointer<Utf8> path, Pointer<Uint8> names, IntPtr size, Int32 options);
typedef _ListDart = int Function(Pointer<Utf8> path, Pointer<Uint8> names, int size, int options);

typedef _GetNative =
    IntPtr Function(
      Pointer<Utf8> path,
      Pointer<Utf8> name,
      Pointer<Void> value,
      IntPtr size,
      Uint32 position,
      Int32 options,
    );
typedef _GetDart =
    int Function(Pointer<Utf8> path, Pointer<Utf8> name, Pointer<Void> value, int size, int position, int options);

typedef _SetNative =
    Int32 Function(
      Pointer<Utf8> path,
      Pointer<Utf8> name,
      Pointer<Void> value,
      IntPtr size,
      Uint32 position,
      Int32 options,
    );
typedef _SetDart =
    int Function(Pointer<Utf8> path, Pointer<Utf8> name, Pointer<Void> value, int size, int position, int options);

typedef _RemoveNative = Int32 Function(Pointer<Utf8> path, Pointer<Utf8> name, Int32 options);
typedef _RemoveDart = int Function(Pointer<Utf8> path, Pointer<Utf8> name, int options);
