import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'ftp_features.dart';

/// Одна запись на той стороне: то немногое, что провайдеру нужно о файле.
///
/// Свой тип, а не тип протокола: провайдер не должен знать ни `MLSD`, ни
/// `LIST`, иначе его нельзя проверить, не подняв сервер. Ровно так же устроен
/// модуль SSH (`SftpEntry`) и модуль 7-Zip — разбор вывода отделён от того,
/// кто этим выводом пользуется.
class FtpEntry {
  const FtpEntry({
    required this.name,
    required this.type,
    this.size = FsNode.unknownSize,
    this.mode = 0,
    this.owner = '',
    this.group = '',
    this.modified,
    this.linkTarget = '',
    this.permissions = '',
  });

  final String name;
  final FileType type;

  /// Размер в байтах; [FsNode.unknownSize] у каталогов и там, где сервер
  /// размера не прислал.
  final int size;

  /// Режим доступа целиком; 0 — сервер о нём не сказал.
  final int mode;

  /// Владелец и группа — **именами**.
  ///
  /// По SFTP так не бывает: там владелец всегда число, а словаря чужой машины
  /// у нас нет. `MLSD` отдаёт имя сразу (`docs/spec/ftp.md`, §3.6).
  final String owner;
  final String group;

  final DateTime? modified;

  /// Куда ведёт ссылка; пусто — это не ссылка или цель неизвестна.
  final String linkTarget;

  /// Что серверу позволено над объектом — буквы факта `perm` из `MLSD`:
  /// `a` дописать, `d` удалить, `f` переименовать, `r` прочитать,
  /// `l` перечислить, `w` создать внутри, `c` создать файл в каталоге.
  ///
  /// Пусто — сервер не сказал, и спрашивать надо попыткой.
  final String permissions;

  bool get isDirectory => type == FileType.directory;

  bool get isLink => type == FileType.symbolicLink;

  /// Можно ли писать в этот объект — по тому, что сказал сам сервер.
  /// null — он не сказал ничего, и врать об этом нельзя.
  bool? get writable {
    if (permissions.isEmpty) {
      return null;
    }
    final letters = permissions.toLowerCase();
    return isDirectory
        ? letters.contains('c') || letters.contains('m')
        : letters.contains('a') || letters.contains('w');
  }
}

/// То, чем провайдер пользуется на той стороне.
///
/// Интерфейс нарочно узкий: чем меньше в нём методов, тем честнее подставка в
/// тестах и тем меньше провайдер знает о протоколе. Все ошибки отсюда выходят
/// уже переведёнными в [FsError] — движок другого языка не понимает.
abstract interface class FtpApi {
  /// Что сервер о себе объявил. Подсказка, а не обещание
  /// (`docs/spec/ftp.md`, §3.2).
  FtpFeatures get features;

  /// Содержимое каталога; «.» и «..» в нём уже нет.
  Future<List<FtpEntry>> listDirectory(String path);

  /// Один объект; null — по этому пути ничего нет.
  ///
  /// Настоящего `stat` у FTP нет: `MLST` есть не у всех, и там, где его нет,
  /// объект ищется в списке своего каталога. Дороже, зато работает везде.
  Future<FtpEntry?> stat(String path);

  Future<Stream<List<int>>> openRead(String path, {int offset = 0});

  Future<StreamSink<List<int>>> openWrite(String path);

  Future<void> makeDirectory(String path);

  Future<void> removeFile(String path);

  Future<void> removeDirectory(String path);

  Future<void> rename(String from, String to);

  Future<void> close();
}
