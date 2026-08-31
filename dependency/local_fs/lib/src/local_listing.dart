import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'package:fc_api/fc_api.dart';

import 'local_mapping.dart';

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
/// `stat` на десятках тысяч файлов заметно блокирует поток, поэтому чтение
/// уходит из основного изолята целиком. Отменить его нельзя — вызывающий код
/// просто игнорирует результат отменённой операции.
///
/// Внутри — **блокирующие** вызовы: изолят за тем и заводится, чтобы в нём
/// можно было блокироваться, а асинхронный ввод-вывод стоил бы дороже самой
/// работы (см. [readDirectoryBlocking]).
Future<List<RawEntry>> readDirectory(String path, {bool includeHidden = false}) {
  return Isolate.run(() => readDirectoryBlocking(path, includeHidden: includeHidden));
}

/// Чтение каталога **блокирующими** вызовами.
///
/// Асинхронный ввод-вывод в Dart не бесплатен: каждый вызов уходит в пул
/// потоков виртуальной машины и возвращается сообщением, и на запись это
/// десятки микросекунд поверх одного-двух на сам системный вызов. Внутри
/// изолята блокироваться можно и нужно — ровно за этим он и заводится.
///
/// Замер (`test/performance/listing_bench_test.dart`, macOS, 8 ядер):
///
/// ```
/// записей   асинхронно   блокирующе
///     100      4.63 мс      2.18 мс
///    1000     40.82 мс      9.33 мс
///   10000    194.24 мс     88.46 мс
/// ```
List<RawEntry> readDirectoryBlocking(String path, {bool includeHidden = false}) {
  final entries = <RawEntry>[];

  final List<FileSystemEntity> listing;
  try {
    listing = Directory(path).listSync(followLinks: false);
  } on FileSystemException catch (error) {
    throw fsErrorFrom(path, error);
  }

  for (final entity in listing) {
    final name = p.basename(entity.path);
    if (!includeHidden && name.startsWith('.')) {
      continue;
    }
    entries.add(_describeBlocking(entity, name));
  }

  return entries;
}

RawEntry _describeBlocking(FileSystemEntity entity, String name) {
  String? linkTarget;
  FileType? linkTargetType;
  final isLink = entity is Link;

  if (isLink) {
    try {
      linkTarget = entity.targetSync();
    } on FileSystemException {
      linkTarget = '';
    }
  }

  FileStat stat;
  try {
    stat = FileStat.statSync(entity.path);
    if (stat.type == FileSystemEntityType.notFound) {
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

  final statType = FileTypeFromIo.fromEntityType(stat.type);
  if (isLink) {
    linkTargetType = statType;
  }
  final fileType = isLink ? FileType.symbolicLink : statType;

  return RawEntry(
    name: name,
    fileType: fileType,
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

/// Переводит ошибку `dart:io` в ошибку дерева.
FsError fsErrorFrom(String path, FileSystemException error) {
  final code = error.osError?.errorCode;
  final kind =
      Platform.isWindows
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
