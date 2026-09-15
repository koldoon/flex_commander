import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'package:fc_api/fc_api.dart';
import 'package:fc_platform/fc_platform.dart';

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
    this.uid,
    this.gid,
    this.owner = '',
    this.group = '',
    this.linkTarget,
    this.linkTargetType,
    this.broken = false,
  });

  final String name;
  final FileType fileType;

  /// Числа владельца и группы; null — своего `stat` здесь нет
  /// (`docs/spec/owner-columns.md`, §3).
  final int? uid;
  final int? gid;

  /// Имена владельца и группы; пусто — система их не назвала.
  final String owner;
  final String group;
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

/// Запись из своего `stat`: режим, размер, времена и владелец разом.
RawEntry _fromOwnStat(
  FileSystemEntity entity,
  String name,
  LocalStatInfo stat, {
  required bool isLink,
  required String? linkTarget,
}) {
  final statType = fileTypeOfMode(stat.mode);
  final fileType = isLink ? FileType.symbolicLink : statType;
  final users = LocalUsers.instance;

  return RawEntry(
    name: name,
    fileType: fileType,
    size: statType == FileType.directory ? -1 : stat.size,
    modified: stat.modified,
    accessed: stat.accessed,
    changed: stat.changed,
    mode: stat.mode,
    modeString: '${fileType.attributeChar}${permissionsOfMode(stat.mode)}',
    // Имена — по числам, а не по файлу: в каталоге из тысяч записей чисел
    // два-три, и словарь их помнит (`LocalUsers`).
    uid: stat.uid,
    gid: stat.gid,
    owner: users?.userName(stat.uid) ?? '',
    group: users?.groupName(stat.gid) ?? '',
    linkTarget: linkTarget,
    linkTargetType: isLink ? statType : null,
  );
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

  // Своим `stat` там, где он есть: `dart:io` зовёт тот же вызов, но чисел
  // владельца из него не отдаёт, и второй вызов ради них удвоил бы их число на
  // каждую запись каталога (`docs/spec/owner-columns.md`, §3).
  final own = LocalStat.instance?.readOf(entity.path);
  if (own != null) {
    return _fromOwnStat(entity, name, own, isLink: isLink, linkTarget: linkTarget);
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
