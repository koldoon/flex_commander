import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'ftp_api.dart';

/// Разбор списков каталога — двух совсем разных форматов.
///
/// `MLSD` (RFC 3659) машинный и однозначный; `LIST` — то, что сервер счёл
/// красивым, и разбирать его приходится догадками. Поэтому `MLSD` пробуется
/// первым, а `LIST` остаётся откатом для тех, кто `MLSD` не умеет
/// (`docs/spec/ftp.md`, §3).
abstract final class FtpListing {
  /// Строка `MLSD`: факты через `;`, потом `'; '`, потом имя.
  ///
  /// Делить надо по **первому** `'; '` и брать имя до конца строки: в именах
  /// бывают и пробелы, и точки с запятой (`docs/spec/ftp.md`, §3.5).
  ///
  /// null — запись не про объект: `type=cdir` и `type=pdir` это «.» и «..»,
  /// и в списке каталога им не место.
  static FtpEntry? parseMachine(String line) {
    final split = line.indexOf('; ');
    if (split < 0) {
      return null;
    }
    final name = line.substring(split + 2);
    if (name.isEmpty) {
      return null;
    }

    final facts = <String, String>{};
    for (final fact in line.substring(0, split).split(';')) {
      if (fact.isEmpty) {
        continue;
      }
      final eq = fact.indexOf('=');
      if (eq > 0) {
        facts[fact.substring(0, eq).toLowerCase()] = fact.substring(eq + 1);
      }
    }

    final kind = facts['type']?.toLowerCase();
    // Свой и родительский каталоги приходят наравне со всеми; списку они не
    // нужны — «..» панель приставляет сама.
    if (kind == 'cdir' || kind == 'pdir') {
      return null;
    }

    final type = switch (kind) {
      'dir' => FileType.directory,
      'file' => FileType.regular,
      // `OS.unix=slink:/цель` — ссылка; цель дочитывается отдельно, как и по
      // SFTP.
      final other? when other.startsWith('os.unix=slink') => FileType.symbolicLink,
      _ => FileType.regular,
    };

    return FtpEntry(
      name: name,
      type: type,
      size: int.tryParse(facts['size'] ?? '') ?? FsNode.unknownSize,
      mode: _mode(facts['unix.mode']),
      owner: facts['unix.ownername'] ?? '',
      group: facts['unix.groupname'] ?? '',
      modified: parseStamp(facts['modify']),
      // Что серверу позволено над объектом — прямой ответ на вопрос «можно ли
      // сюда писать», который иначе выясняется попыткой.
      permissions: facts['perm'] ?? '',
    );
  }

  /// Режим доступа из `UNIX.mode`: восьмеричное, бывает с ведущим нулём и с
  /// битом `setgid` (`02755`).
  static int _mode(String? value) {
    if (value == null || value.isEmpty) {
      return 0;
    }
    return int.tryParse(value, radix: 8) ?? 0;
  }

  /// Время из `modify`/`MDTM`: `YYYYMMDDHHMMSS`, всегда UTC (RFC 3659, §2.3).
  ///
  /// Бывает с дробной частью — `20200926030759.123`; она нам не нужна, но и
  /// ронять разбор из-за неё нельзя.
  static DateTime? parseStamp(String? value) {
    if (value == null || value.length < 14) {
      return null;
    }
    final digits = value.substring(0, 14);
    final stamp = int.tryParse(digits);
    if (stamp == null) {
      return null;
    }
    int at(int from, int to) => int.parse(digits.substring(from, to));
    try {
      return DateTime.utc(at(0, 4), at(4, 6), at(6, 8), at(8, 10), at(10, 12), at(12, 14)).toLocal();
    } on Object {
      return null;
    }
  }

  /// Строка `LIST` — юниксовая или досовская; null — ни то ни другое.
  static FtpEntry? parseText(String line, {DateTime? now}) {
    if (line.trim().isEmpty) {
      return null;
    }
    return _parseUnix(line, now ?? DateTime.now()) ?? _parseDos(line);
  }

  /// Юниксовый формат: права, число ссылок, владелец, группа, размер, дата из
  /// трёх полей, имя.
  ///
  /// ```
  /// -rw-r--r--   1 33  33   3491840 Sep  1  2025 c1600-K8osy-Mz 122-15 T5.bin
  /// drwxr-sr-x   7 33  33         7 May  1 05:01 10k
  /// lrwxrwxrwx   1 0   0          9 Jan  3  2024 latest -> current/x.bin
  /// ```
  ///
  /// **Имя начинается с девятого поля и идёт до конца строки.** Разбор через
  /// `split` теряет всё после первого пробела, а имена с пробелами на живом
  /// сервере — обычное дело (`docs/spec/ftp.md`, §3.5).
  static FtpEntry? _parseUnix(String line, DateTime now) {
    final mode = _unixMode(line);
    if (mode == null) {
      return null;
    }

    // Восемь полей до имени; девятое и всё, что за ним, — имя.
    final fields = <String>[];
    var at = 0;
    while (fields.length < 8) {
      while (at < line.length && line[at] == ' ') {
        at++;
      }
      final start = at;
      while (at < line.length && line[at] != ' ') {
        at++;
      }
      if (start == at) {
        return null;
      }
      fields.add(line.substring(start, at));
    }
    while (at < line.length && line[at] == ' ') {
      at++;
    }
    if (at >= line.length) {
      return null;
    }

    var name = line.substring(at);
    final type = switch (line[0]) {
      'd' => FileType.directory,
      'l' => FileType.symbolicLink,
      _ => FileType.regular,
    };

    String target = '';
    if (type == FileType.symbolicLink) {
      final arrow = name.indexOf(' -> ');
      if (arrow >= 0) {
        target = name.substring(arrow + 4);
        name = name.substring(0, arrow);
      }
    }

    return FtpEntry(
      name: name,
      type: type,
      size: type == FileType.directory ? FsNode.unknownSize : int.tryParse(fields[4]) ?? FsNode.unknownSize,
      mode: mode,
      owner: fields[2],
      group: fields[3],
      modified: _unixStamp(fields[5], fields[6], fields[7], now),
      linkTarget: target,
    );
  }

  /// Режим из первых десяти символов `drwxr-sr-x`; null — строка не отсюда.
  static int? _unixMode(String line) {
    if (line.length < 11 || line[10] != ' ') {
      return null;
    }
    const kinds = 'bcdlps-';
    if (!kinds.contains(line[0])) {
      return null;
    }

    var mode = 0;
    for (var group = 0; group < 3; group++) {
      final at = 1 + group * 3;
      var bits = 0;
      if (line[at] == 'r') {
        bits |= 4;
      } else if (line[at] != '-') {
        return null;
      }
      if (line[at + 1] == 'w') {
        bits |= 2;
      } else if (line[at + 1] != '-') {
        return null;
      }
      // Третий разряд несёт сразу два: право на исполнение и особый бит.
      switch (line[at + 2]) {
        case 'x':
          bits |= 1;
        case 's':
        case 't':
          bits |= 1;
          mode |=
              group == 0
                  ? 2048
                  : group == 1
                  ? 1024
                  : 512;
        case 'S':
        case 'T':
          mode |=
              group == 0
                  ? 2048
                  : group == 1
                  ? 1024
                  : 512;
        case '-':
          break;
        default:
          return null;
      }
      mode |= bits << ((2 - group) * 3);
    }
    return mode;
  }

  /// Дата из трёх полей: `Sep  1  2025` или `May  1 05:01`.
  ///
  /// Года в свежих записях нет — вместо него время, а год подразумевается
  /// текущий. Дата в будущем при этом значит прошлый год: так делает `ls`, и
  /// иначе файл, тронутый в декабре, в январе уезжает на год вперёд.
  static DateTime? _unixStamp(String month, String day, String last, DateTime now) {
    final index = _months.indexOf(month.toLowerCase());
    if (index < 0) {
      return null;
    }
    final date = int.tryParse(day);
    if (date == null) {
      return null;
    }

    final year = int.tryParse(last);
    if (year != null && last.length == 4) {
      return DateTime(year, index + 1, date);
    }

    final colon = last.indexOf(':');
    if (colon < 0) {
      return null;
    }
    final hour = int.tryParse(last.substring(0, colon));
    final minute = int.tryParse(last.substring(colon + 1));
    if (hour == null || minute == null) {
      return null;
    }
    final guess = DateTime(now.year, index + 1, date, hour, minute);
    return guess.isAfter(now.add(const Duration(days: 1)))
        ? DateTime(now.year - 1, index + 1, date, hour, minute)
        : guess;
  }

  static const List<String> _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// Досовский формат IIS: `03-07-24  10:22AM       <DIR>          pub`.
  static FtpEntry? _parseDos(String line) {
    final match = _dos.firstMatch(line);
    if (match == null) {
      return null;
    }
    final name = match.group(5)!;
    if (name.isEmpty) {
      return null;
    }
    final size = match.group(4);
    return FtpEntry(
      name: name,
      type: size == null ? FileType.directory : FileType.regular,
      size: size == null ? FsNode.unknownSize : int.tryParse(size) ?? FsNode.unknownSize,
      modified: _dosStamp(match.group(1)!, match.group(2)!, match.group(3)!),
    );
  }

  static final RegExp _dos = RegExp(
    r'^(\d{2}-\d{2}-\d{2,4})\s+(\d{1,2}:\d{2})\s*([AaPp][Mm])?\s+(?:<DIR>|(\d+))\s+(.+)$',
  );

  static DateTime? _dosStamp(String date, String time, String half) {
    final parts = date.split('-');
    if (parts.length != 3) {
      return null;
    }
    final month = int.tryParse(parts[0]);
    final day = int.tryParse(parts[1]);
    var year = int.tryParse(parts[2]);
    if (month == null || day == null || year == null) {
      return null;
    }
    // Двузначный год: до 70 — этот век, дальше — прошлый. Так же считает IIS.
    if (parts[2].length == 2) {
      year += year < 70 ? 2000 : 1900;
    }

    final clock = time.split(':');
    var hour = int.tryParse(clock[0]) ?? 0;
    final minute = int.tryParse(clock[1]) ?? 0;
    final afternoon = half.toLowerCase() == 'pm';
    if (afternoon && hour < 12) {
      hour += 12;
    } else if (!afternoon && half.isNotEmpty && hour == 12) {
      hour = 0;
    }
    return DateTime(year, month, day, hour, minute);
  }
}
