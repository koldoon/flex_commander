import 'dart:io';

import 'file_type.dart';

/// Права доступа и флаги объекта файловой системы.
///
/// На unix-подобных системах строится из режима доступа: [modeString] — это то,
/// что показывает колонка «Атрибуты» ("drwxr-xr-x"). На Windows режим доступа
/// малоинформативен, там используется [FileAttributes.windows] с флагами RHSA.
class FileAttributes {
  const FileAttributes({required this.mode, required this.modeString});

  /// Пустые атрибуты: объект не удалось прочитать.
  const FileAttributes.unknown()
      : mode = 0,
        modeString = '';

  /// Атрибуты Windows: read-only, hidden, system, archive.
  FileAttributes.windows({
    bool readOnly = false,
    bool hidden = false,
    bool system = false,
    bool archive = false,
  })  : mode = 0,
        modeString = [
          if (readOnly) 'R' else '-',
          if (hidden) 'H' else '-',
          if (system) 'S' else '-',
          if (archive) 'A' else '-',
        ].join();

  /// `FileStat.modeString()` возвращает только девять символов прав
  /// («rw-r--r--»), без первого символа типа, поэтому тип подставляется сам.
  factory FileAttributes.fromStat(FileStat stat, {FileType? type}) {
    final fileType = type ?? FileType.fromEntityType(stat.type);
    return FileAttributes(
      mode: stat.mode,
      modeString: '${fileType.attributeChar}${stat.modeString()}',
    );
  }

  /// Режим доступа из `FileStat.mode`.
  final int mode;

  /// Строка атрибутов для показа в панели.
  final String modeString;

  /// Права владельца файла. Проверять доступ по ним не следует — реальные права
  /// зависят от того, кто именно открывает файл; для этого есть попытка чтения.
  bool get isReadable => mode & 0x100 != 0; // S_IRUSR

  bool get isWritable => mode & 0x080 != 0; // S_IWUSR

  bool get isExecutable => mode & 0x040 != 0; // S_IXUSR

  @override
  String toString() => modeString;
}
