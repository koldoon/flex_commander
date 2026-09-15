import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'sftp_api.dart';

/// Запись сервера — узлом дерева.
///
/// Тип цели ([linkTargetType]) известен не всегда: за ним нужен отдельный
/// вопрос серверу, и листинг спрашивает его только про ссылки.
FsNode nodeFromEntry(SftpEntry entry, FsNode parent, TreeProvider provider, {FileType? linkTargetType}) {
  final attributes =
      entry.mode == 0
          ? const FileAttributes.unknown()
          : FileAttributes.fromMode(
            entry.mode,
            permissionsOf(entry.mode),
            entry.type,
            // Числа сервер присылает вместе с режимом; имён SFTP не даёт — их
            // там, где сервер их не назвал, не будет
            // (`docs/spec/owner-columns.md`, §3).
            uid: entry.uid,
            gid: entry.gid,
          );

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
/// Общее правило (`permissionsOfMode` в `fc_api`): режим приезжает числом и от
/// сервера, и от своего `stat`, и из архива — разбирать его по-разному значит
/// однажды показать один и тот же файл двумя способами.
String permissionsOf(int mode) => permissionsOfMode(mode);
