/// Что сервер о себе объявил в ответ на `FEAT`.
///
/// **Подсказка, а не обещание.** Сервер из разведки объявляет `AUTH TLS` и на
/// саму команду отвечает `534 Unwilling to accept security parameters`.
/// Поэтому по этому значению решают, что **пробовать**, а правду говорит
/// только ответ на команду (`docs/spec/ftp.md`, §3.2).
class FtpFeatures {
  FtpFeatures(Iterable<String> lines) : _names = {for (final line in lines) _nameOf(line)}..remove('');

  /// Сервер `FEAT` не понял: считаем, что не умеет ничего сверх RFC 959.
  FtpFeatures.none() : _names = const {};

  final Set<String> _names;

  /// Первое слово строки возможностей: `REST STREAM` → `REST`,
  /// `MLST modify*;size*;` → `MLST`.
  static String _nameOf(String line) {
    final trimmed = line.trim().toUpperCase();
    final space = trimmed.indexOf(' ');
    return space < 0 ? trimmed : trimmed.substring(0, space);
  }

  bool has(String name) => _names.contains(name.toUpperCase());

  /// Машинный список каталога. Объявляется как `MLST` — `MLSD` в списке
  /// возможностей отдельной строкой не стоит, хотя команд две (RFC 3659, §7).
  bool get machineListing => has('MLST') || has('MLSD');

  /// Докачка: `REST STREAM`. Работает только в двоичном режиме
  /// (`docs/spec/ftp.md`, §3.3).
  bool get restart => has('REST');

  /// Поставить дату изменения.
  bool get setModified => has('MFMT');

  /// Точная дата чтением.
  bool get modificationTime => has('MDTM');

  /// Размер одной командой.
  bool get size => has('SIZE');

  /// Расширенный пассивный режим.
  bool get extendedPassive => has('EPSV');

  /// Имена в UTF-8 — после `OPTS UTF8 ON`.
  bool get utf8 => has('UTF8');

  /// Явный TLS. Пробовать стоит, верить — нет.
  bool get authTls => has('AUTH');

  @override
  String toString() => 'FtpFeatures(${(_names.toList()..sort()).join(', ')})';
}
