import 'package:fc_api/fc_api.dart';

/// Девять символов прав из режима доступа: «rwxr-xr-x».
///
/// Своя копия, а не общая с модулем SSH: связывать два независимых модуля ради
/// десяти строк дороже, чем повторить, — тем же доводом в `providers.md`
/// кончается разговор про трёх архиваторов. `FileAttributes.fromMode` ждёт уже
/// готовую строку, а `dart:io` над чужой машиной не работает: режим приезжает
/// числом по протоколу.
String permissionsOf(int mode) {
  const letters = 'rwxrwxrwx';
  final buffer = StringBuffer();
  for (var i = 0; i < letters.length; i++) {
    // Старший из девяти битов — чтение владельцем (0400).
    buffer.write(mode & (1 << (letters.length - 1 - i)) != 0 ? letters[i] : '-');
  }
  return buffer.toString();
}

/// Атрибуты строки списка; режим 0 — сервер о нём не сказал, и выдумывать
/// прочерки нельзя: пустое честнее.
FileAttributes attributesOf(int mode, FileType type) =>
    mode == 0 ? const FileAttributes.unknown() : FileAttributes.fromMode(mode, permissionsOf(mode), type);
