import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Имена пользователей и групп системы — `getpwuid(3)` и соседи.
///
/// **Не разбором `/etc/passwd`**, как предполагал план. На macOS этого файла
/// для дела не хватает: там лежат только служебные записи (`root`, `daemon`,
/// `_www`), а обычный пользователь живёт в Directory Services, и `501` так и
/// осталось бы числом — то есть словарь не работал бы ровно в том случае, ради
/// которого заводится. `getpwuid` же спрашивает систему целиком, каким бы
/// способом она ни хранила своих пользователей: тот же ответ, что у `id -un`.
///
/// Читается **только имя и число**: `pw_name` лежит первым полем структуры, а
/// `pw_uid` — третьим, и дальше нужного мы не заглядываем.
class LocalUsers {
  LocalUsers._(this._getpwuid, this._getgrgid, this._getpwnam, this._getgrnam);

  static LocalUsers? _instance;
  static bool _looked = false;

  /// null — на этой платформе пользователей в этом смысле нет (Windows).
  static LocalUsers? get instance {
    if (_looked) {
      return _instance;
    }
    _looked = true;
    if (Platform.isWindows) {
      return null;
    }
    final process = DynamicLibrary.process();
    return _instance = LocalUsers._(
      process.lookupFunction<_ByIdNative<_Passwd>, _ByIdDart<_Passwd>>('getpwuid'),
      process.lookupFunction<_ByIdNative<_Group>, _ByIdDart<_Group>>('getgrgid'),
      process.lookupFunction<_ByNameNative<_Passwd>, _ByNameDart<_Passwd>>('getpwnam'),
      process.lookupFunction<_ByNameNative<_Group>, _ByNameDart<_Group>>('getgrnam'),
    );
  }

  final _ByIdDart<_Passwd> _getpwuid;
  final _ByIdDart<_Group> _getgrgid;
  final _ByNameDart<_Passwd> _getpwnam;
  final _ByNameDart<_Group> _getgrnam;

  /// Ответы запоминаются на всё время работы приложения.
  ///
  /// Спрашивают об одних и тех же числах снова и снова — у всех файлов
  /// каталога владелец обычно один, — а `getpwuid` при каждом промахе кэша
  /// системы ходит в Directory Services.
  final Map<int, String> _users = {};
  final Map<int, String> _groups = {};

  /// Имя пользователя; пусто — система такого не знает.
  String userName(int uid) => _users[uid] ??= _nameAt(_getpwuid(uid).cast<Pointer<Utf8>>());

  /// Имя группы; пусто — система такой не знает.
  String groupName(int gid) => _groups[gid] ??= _nameAt(_getgrgid(gid).cast<Pointer<Utf8>>());

  /// Число по имени; null — такого пользователя нет.
  int? userId(String name) {
    final native = name.toNativeUtf8();
    try {
      final entry = _getpwnam(native);
      return entry == nullptr ? null : entry.ref.uid;
    } finally {
      calloc.free(native);
    }
  }

  /// Число по имени группы; null — такой группы нет.
  int? groupId(String name) {
    final native = name.toNativeUtf8();
    try {
      final entry = _getgrnam(native);
      return entry == nullptr ? null : entry.ref.gid;
    } finally {
      calloc.free(native);
    }
  }

  /// Имя лежит первым полем и у пользователя, и у группы — отсюда один разбор
  /// на оба случая.
  ///
  /// Строка принадлежит системе и живёт до следующего такого же вызова,
  /// поэтому копируется сразу.
  static String _nameAt(Pointer<Pointer<Utf8>> entry) {
    if (entry == nullptr) {
      return '';
    }
    final name = entry.value;
    return name == nullptr ? '' : name.toDartString();
  }
}

/// Начало `struct passwd`: имя, пароль, число. Дальше не заглядываем.
final class _Passwd extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> password;

  @Uint32()
  external int uid;
}

/// Начало `struct group`: имя, пароль, число.
final class _Group extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> password;

  @Uint32()
  external int gid;
}

typedef _ByIdNative<T extends Struct> = Pointer<T> Function(Uint32 id);
typedef _ByIdDart<T extends Struct> = Pointer<T> Function(int id);

typedef _ByNameNative<T extends Struct> = Pointer<T> Function(Pointer<Utf8> name);
typedef _ByNameDart<T extends Struct> = Pointer<T> Function(Pointer<Utf8> name);
