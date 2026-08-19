import 'package:fc_api/fc_api.dart';

import 'sftp_api.dart';

/// Запись сервера — узлом дерева.
///
/// Тип цели ([linkTargetType]) известен не всегда: за ним нужен отдельный
/// вопрос серверу, и листинг спрашивает его только про ссылки.
FsNode nodeFromEntry(SftpEntry entry, FsNode parent, TreeProvider provider, {FileType? linkTargetType}) {
  final attributes = entry.mode == 0
      ? const FileAttributes.unknown()
      : FileAttributes.fromMode(entry.mode, permissionsOf(entry.mode), entry.type);

  return switch (entry.type) {
    FileType.symbolicLink => LinkNode(
      provider: provider,
      name: entry.name,
      parent: parent,
      reference: entry.linkTarget ?? '',
      targetType: linkTargetType,
      size: entry.size,
      attributes: attributes,
      modified: entry.modified,
      accessed: entry.accessed,
      executable: attributes.isExecutable,
      // Ссылка, о цели которой спросили и не нашли, — битая. Про ту, о цели
      // которой не спрашивали, врать нечего.
      broken: entry.linkTarget != null && linkTargetType == null,
    ),
    FileType.directory => DirectoryNode(
      provider: provider,
      name: entry.name,
      parent: parent,
      attributes: attributes,
      modified: entry.modified,
      accessed: entry.accessed,
    ),
    _ => FileNode(
      provider: provider,
      name: entry.name,
      parent: parent,
      size: entry.size,
      fileType: entry.type,
      attributes: attributes,
      modified: entry.modified,
      accessed: entry.accessed,
      executable: attributes.isExecutable,
    ),
  };
}

/// Девять символов прав из режима доступа: «rwxr-xr-x».
///
/// Пишется здесь, а не берётся из API: `FileAttributes.fromMode` ждёт уже
/// готовую строку, а `dart:io` с его `FileStat.modeString` над чужой машиной не
/// работает — режим приезжает числом по протоколу.
String permissionsOf(int mode) {
  const letters = 'rwxrwxrwx';
  final buffer = StringBuffer();
  for (var i = 0; i < letters.length; i++) {
    // Старший из девяти битов — чтение владельцем (0400).
    buffer.write(mode & (1 << (letters.length - 1 - i)) != 0 ? letters[i] : '-');
  }
  return buffer.toString();
}
