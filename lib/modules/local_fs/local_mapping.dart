import 'dart:io';

import 'package:fc_api/fc_api.dart';

/// Перевод с языка `dart:io` на язык дерева узлов.
///
/// В API этого нет намеренно: `FileType` и `FileAttributes` описывают объект
/// любого происхождения — файл на диске, запись в архиве, строку с сервера, —
/// а `FileSystemEntityType` и `FileStat` бывают только у настоящего диска.
extension FileTypeFromIo on FileType {
  /// Разбор типа из `dart:io`.
  static FileType fromEntityType(FileSystemEntityType type) {
    return switch (type) {
      FileSystemEntityType.file => FileType.regular,
      FileSystemEntityType.directory => FileType.directory,
      FileSystemEntityType.link => FileType.symbolicLink,
      FileSystemEntityType.pipe => FileType.fifo,
      FileSystemEntityType.unixDomainSock => FileType.socket,
      _ => FileType.unknown,
    };
  }
}

/// Атрибуты из `FileStat`.
///
/// `FileStat.modeString()` возвращает только девять символов прав
/// («rw-r--r--»), без первого символа типа, поэтому тип подставляется сам.
FileAttributes attributesFromStat(FileStat stat, {FileType? type}) {
  final fileType = type ?? FileTypeFromIo.fromEntityType(stat.type);
  return FileAttributes.fromMode(stat.mode, stat.modeString(), fileType);
}
