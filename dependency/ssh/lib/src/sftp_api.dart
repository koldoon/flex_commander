import 'dart:async';

import 'package:fc_api/fc_api.dart';

/// Одна запись на той стороне: то немногое, что провайдеру нужно о файле.
///
/// Свой тип, а не тип библиотеки: провайдер не должен зависеть от `dartssh2`,
/// иначе его нельзя проверить, не подняв сервер. Ровно так же устроен модуль
/// 7-Zip — разбор вывода программы отделён от того, кто этим выводом
/// пользуется.
class SftpEntry {
  const SftpEntry({
    required this.name,
    required this.type,
    this.size = FsNode.unknownSize,
    this.mode = 0,
    this.modified,
    this.accessed,
    this.linkTarget,
  });

  final String name;
  final FileType type;

  /// Размер в байтах; [FsNode.unknownSize] у каталогов и там, где сервер
  /// размера не прислал.
  final int size;

  /// Режим доступа целиком, как его отдал сервер. 0 — атрибутов нет.
  final int mode;

  final DateTime? modified;
  final DateTime? accessed;

  /// Куда ведёт ссылка; null — это не ссылка.
  final String? linkTarget;

  bool get isDirectory => type == FileType.directory;

  bool get isLink => type == FileType.symbolicLink;
}

/// То, чем провайдер пользуется на той стороне.
///
/// Интерфейс нарочно узкий: чем меньше в нём методов, тем честнее подставка в
/// тестах и тем меньше провайдер знает о протоколе. Все ошибки отсюда выходят
/// уже переведёнными в [FsError] — движок другого языка не понимает.
abstract interface class SftpApi {
  /// Атрибуты объекта; null — по этому пути ничего нет.
  ///
  /// [followLink] — спрашивать о цели ссылки, а не о ней самой.
  Future<SftpEntry?> stat(String path, {bool followLink = false});

  /// Содержимое каталога без «.» и «..».
  Future<List<SftpEntry>> listDirectory(String path);

  /// Куда ведёт ссылка.
  Future<String?> readLink(String path);

  Future<void> makeDirectory(String path);

  /// Удаляет файл или ссылку — саму ссылку, не её цель.
  Future<void> removeFile(String path);

  /// Удаляет пустой каталог.
  Future<void> removeDirectory(String path);

  Future<void> rename(String from, String to);

  /// Содержимое файла потоком, начиная с [offset].
  Future<Stream<List<int>>> openRead(String path, {int offset = 0});

  /// Приёмник для нового файла: существующий обрезается.
  Future<StreamSink<List<int>>> openWrite(String path);

  /// Абсолютный путь: `.` — это дом пользователя на сервере.
  Future<String> absolute(String path);

  Future<void> close();
}
