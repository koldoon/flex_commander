import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../file_type.dart';
import '../tree_provider.dart';

/// Сырая запись каталога: только данные, без узлов дерева.
///
/// Узлы строятся из этих записей уже в основном изоляте, потому что узел ссылается
/// на провайдера и на родителя, а такие связи через границу изолята не переносят.
class RawEntry {
  RawEntry({
    required this.name,
    required this.fileType,
    this.size = -1,
    this.modified,
    this.accessed,
    this.changed,
    this.mode = 0,
    this.modeString = '',
    this.linkTarget,
    this.linkTargetType,
    this.broken = false,
  });

  final String name;
  final FileType fileType;
  final int size;
  final DateTime? modified;
  final DateTime? accessed;

  /// Время последнего изменения метаданных (ctime). Настоящей даты создания
  /// `dart:io` не даёт ни на одной платформе, поэтому колонка «Создан»
  /// показывает именно это значение.
  final DateTime? changed;

  final int mode;
  final String modeString;

  /// Для ссылки — строка, на которую она указывает.
  final String? linkTarget;

  /// Для ссылки — тип объекта, на который она указывает; null у битой ссылки.
  final FileType? linkTargetType;

  /// Запись не удалось прочитать целиком: нет прав или объект исчез.
  final bool broken;
}

/// Читает каталог в отдельном изоляте.
///
/// `stat()` на десятках тысяч файлов заметно блокирует поток, поэтому чтение
/// уходит из основного изолята целиком. Отменить его нельзя — вызывающий код
/// просто игнорирует результат отменённой операции.
Future<List<RawEntry>> readDirectory(
  String path, {
  bool includeHidden = false,
}) {
  return Isolate.run(() => readDirectorySync(path, includeHidden: includeHidden));
}

/// Тело чтения каталога. Вынесено отдельно, чтобы вызываться и без изолята
/// (в тестах) и внутри [Isolate.run].
Future<List<RawEntry>> readDirectorySync(
  String path, {
  bool includeHidden = false,
}) async {
  final directory = Directory(path);
  final entries = <RawEntry>[];

  final Stream<FileSystemEntity> listing;
  try {
    listing = directory.list(followLinks: false);
  } on FileSystemException catch (error) {
    throw _toFsError(path, error);
  }

  try {
    await for (final entity in listing) {
      final name = p.basename(entity.path);
      if (!includeHidden && name.startsWith('.')) {
        continue;
      }
      entries.add(await _describe(entity, name));
    }
  } on FileSystemException catch (error) {
    throw _toFsError(path, error);
  }

  return entries;
}

Future<RawEntry> _describe(FileSystemEntity entity, String name) async {
  // Ссылка описывается данными своей цели, но остаётся ссылкой: так в панели
  // сразу виден и размер цели, и то, что перед нами именно ссылка.
  String? linkTarget;
  FileType? linkTargetType;
  final isLink = entity is Link;

  if (isLink) {
    try {
      linkTarget = await entity.target();
    } on FileSystemException {
      linkTarget = '';
    }
  }

  FileStat stat;
  try {
    stat = await FileStat.stat(entity.path);
    if (stat.type == FileSystemEntityType.notFound) {
      // Битая ссылка или объект исчез между list() и stat().
      return RawEntry(
        name: name,
        fileType: isLink ? FileType.symbolicLink : FileType.unknown,
        linkTarget: linkTarget,
        broken: true,
      );
    }
  } on FileSystemException {
    return RawEntry(
      name: name,
      fileType: isLink ? FileType.symbolicLink : FileType.unknown,
      linkTarget: linkTarget,
      broken: true,
    );
  }

  final statType = FileType.fromEntityType(stat.type);
  if (isLink) {
    linkTargetType = statType;
  }
  final fileType = isLink ? FileType.symbolicLink : statType;

  return RawEntry(
    name: name,
    fileType: fileType,
    // Размер каталога — это размер его записи в ФС, для панели он бесполезен.
    size: statType == FileType.directory ? -1 : stat.size,
    modified: stat.modified,
    accessed: stat.accessed,
    changed: stat.changed,
    mode: stat.mode,
    modeString: '${fileType.attributeChar}${stat.modeString()}',
    linkTarget: linkTarget,
    linkTargetType: linkTargetType,
  );
}

FsError _toFsError(String path, FileSystemException error) {
  final code = error.osError?.errorCode;
  final kind = Platform.isWindows
      ? switch (code) {
          2 || 3 => FsErrorKind.notFound, // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND
          5 => FsErrorKind.permissionDenied, // ERROR_ACCESS_DENIED
          267 => FsErrorKind.notADirectory, // ERROR_DIRECTORY
          _ => FsErrorKind.io,
        }
      : switch (code) {
          2 => FsErrorKind.notFound, // ENOENT
          13 => FsErrorKind.permissionDenied, // EACCES
          20 => FsErrorKind.notADirectory, // ENOTDIR
          _ => FsErrorKind.io,
        };
  return FsError(path, kind, error);
}
