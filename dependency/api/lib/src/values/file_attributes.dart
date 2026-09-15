import 'file_type.dart';

/// Права доступа и флаги объекта файловой системы.
///
/// На unix-подобных системах строится из режима доступа: [modeString] — это то,
/// что показывает колонка «Атрибуты» ("drwxr-xr-x"). На Windows режим доступа
/// малоинформативен, там используется [FileAttributes.windows] с флагами RHSA.
class FileAttributes {
  const FileAttributes({
    required this.mode,
    required this.modeString,
    this.uid,
    this.gid,
    this.owner = '',
    this.group = '',
  });

  /// Пустые атрибуты: объект не удалось прочитать.
  const FileAttributes.unknown() : mode = 0, modeString = '', uid = null, gid = null, owner = '', group = '';

  /// Атрибуты Windows: read-only, hidden, system, archive.
  FileAttributes.windows({bool readOnly = false, bool hidden = false, bool system = false, bool archive = false})
    : mode = 0,
      uid = null,
      gid = null,
      owner = '',
      group = '',
      modeString =
          [
            if (readOnly) 'R' else '-',
            if (hidden) 'H' else '-',
            if (system) 'S' else '-',
            if (archive) 'A' else '-',
          ].join();

  /// Права из режима доступа: девять символов («rw-r--r--») плюс символ типа.
  ///
  /// Разбор `FileStat` живёт в модуле локальной файловой системы: `dart:io`
  /// в API нет — провайдер может стоять и над сетью, и над архивом.
  factory FileAttributes.fromMode(
    int mode,
    String permissions,
    FileType type, {
    int? uid,
    int? gid,
    String owner = '',
    String group = '',
  }) {
    return FileAttributes(
      mode: mode,
      modeString: '${type.attributeChar}$permissions',
      uid: uid,
      gid: gid,
      owner: owner,
      group: group,
    );
  }

  /// Режим доступа из `FileStat.mode`.
  final int mode;

  /// Строка атрибутов для показа в панели.
  final String modeString;

  /// Числа владельца и группы; null — источник их не знает
  /// (`docs/spec/owner-columns.md`, §3).
  final int? uid;
  final int? gid;

  /// Имена владельца и группы; пусто — источник не знает имён.
  ///
  /// Имя и число хранятся рядом, а не вместо: показать можно и то и другое, а
  /// выбор между ними — дело формата колонки (Б3). Пока показывается имя, а
  /// число — там, где имени нет.
  final String owner;
  final String group;

  /// Что показать в колонке владельца: имя, число или ничего.
  ///
  /// Здесь, а не у колонки: тем же правилом живут и окно сведений, и окно
  /// атрибутов, — а три места, решающих одно, однажды разойдутся.
  String get ownerText => owner.isNotEmpty ? owner : (uid?.toString() ?? '');

  String get groupText => group.isNotEmpty ? group : (gid?.toString() ?? '');

  /// Права владельца файла. Проверять доступ по ним не следует — реальные права
  /// зависят от того, кто именно открывает файл; для этого есть попытка чтения.
  bool get isReadable => mode & 0x100 != 0; // S_IRUSR

  bool get isWritable => mode & 0x080 != 0; // S_IWUSR

  bool get isExecutable => mode & 0x040 != 0; // S_IXUSR

  @override
  String toString() => modeString;
}

/// Девять символов прав из режима доступа: «rwxr-xr-x».
///
/// Одно правило на всё приложение: режим приезжает числом отовсюду — от своего
/// `stat`, от SFTP, из архива, — и разбирать его по-разному значит однажды
/// показать один и тот же файл двумя способами.
String permissionsOfMode(int mode) {
  const letters = 'rwxrwxrwx';
  final buffer = StringBuffer();
  for (var i = 0; i < letters.length; i++) {
    // Старший из девяти битов — чтение владельцем (0400).
    buffer.write(mode & (1 << (letters.length - 1 - i)) != 0 ? letters[i] : '-');
  }
  return buffer.toString();
}

/// Тип объекта из режима доступа — по маске `S_IFMT`.
///
/// Нужен там, где тип не назвали отдельно: свой `stat` отдаёт режим и ничего
/// больше, а `dart:io` о типе рассказывает сам.
FileType fileTypeOfMode(int mode) => switch (mode & 0xF000) {
  0x4000 => FileType.directory,
  0xA000 => FileType.symbolicLink,
  0x1000 => FileType.fifo,
  0xC000 => FileType.socket,
  0x2000 => FileType.characterSpecial,
  0x6000 => FileType.blockSpecial,
  0x8000 => FileType.regular,
  _ => FileType.unknown,
};
