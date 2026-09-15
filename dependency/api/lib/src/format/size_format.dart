const List<String> _units = ['', 'K', 'M', 'G', 'T', 'P'];

/// Как показать размер в колонке (`docs/spec/column-formats.md`, §4).
enum SizeFormat {
  /// `6.0K` — сокращение по 1024, как в макете, и потому умолчание.
  auto('auto'),

  /// `6 144` — до последнего байта, с разбивкой по тысячам.
  bytes('bytes'),

  /// `6.0 KB` — двоичные единицы: делим на 1024.
  binary('binary'),

  /// `6.3 kB` — десятичные: делим на 1000. Подпись у них своя нарочно:
  /// единица, названная одинаково при разном основании, — это обман.
  decimal('decimal');

  const SizeFormat(this.id);

  /// Имя формата в раскладке колонки и в настройках.
  final String id;

  /// Формат по имени; незнакомое — умолчание.
  static SizeFormat byId(String id) {
    for (final format in values) {
      if (format.id == id) {
        return format;
      }
    }
    return auto;
  }
}

/// Неразрывный пробел — разделитель тысяч.
const String _group = '\u00a0';

/// Размер для колонки панели: `126`, `6.0K`, `90.1K`, `14.9M`, `999.9G`.
///
/// Основание 1024; байты — без суффикса и дробной части, дальше **всегда** один
/// знак после запятой, даже нулевой.
///
/// Ноль печатается нарочно. Растущая сумма обходимого каталога меняется по
/// десять раз в секунду, и на круглом значении число дёргалось формой и
/// шириной: `71.9M` → `72M` → `72.1M`. Постоянный знак стоит одного лишнего
/// символа и снимает это дёрганье целиком.
///
/// Отрицательный размер ([FsNode.unknownSize]) даёт пустую строку: у каталогов
/// и псевдоузла «..» размера нет.
String formatSize(int bytes, [SizeFormat format = SizeFormat.auto]) {
  if (bytes < 0) {
    return '';
  }
  switch (format) {
    case SizeFormat.bytes:
      // Без «B»: в колонке подпись единицы у каждой строки — это шум, а что
      // это байты, сказано заголовком.
      return _grouped(bytes);
    case SizeFormat.binary:
      return _scaled(bytes, 1024, 'B');
    case SizeFormat.decimal:
      return _scaled(bytes, 1000, 'B', lowerFirst: true);
    case SizeFormat.auto:
      break;
  }
  if (bytes < 1024) {
    return '$bytes';
  }

  var value = bytes / 1024;
  var unit = 1;

  // Округление до одного знака может дать 1024.0 — тогда переходим к следующей
  // единице, чтобы не показывать «1024.0K».
  while (unit < _units.length - 1 && _roundToTenth(value) >= 1024) {
    value /= 1024;
    unit++;
  }

  return '${_roundToTenth(value).toStringAsFixed(1)}${_units[unit]}';
}

/// Размер для строки состояния: `1.2 GB`, `914 B`.
String formatBytesLong(int bytes) {
  if (bytes < 0) {
    return '';
  }
  if (bytes < 1024) {
    return '$bytes B';
  }

  var value = bytes / 1024;
  var unit = 1;
  while (unit < _units.length - 1 && _roundToTenth(value) >= 1024) {
    value /= 1024;
    unit++;
  }

  return '${_roundToTenth(value).toStringAsFixed(1)} ${_units[unit]}B';
}

double _roundToTenth(double value) => (value * 10).roundToDouble() / 10;

/// Число с разбивкой по тысячам неразрывными пробелами.
String _grouped(int value) {
  final digits = value.toString();
  final parts = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    parts.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
  }
  return parts.join(_group);
}

/// Размер в единицах названного основания: `6.0 KB`, `6.3 kB`.
///
/// [lowerFirst] — строчная первая буква у десятичных (`kB`): так их и
/// различают на письме, и различие это не косметическое — основание разное.
String _scaled(int bytes, int base, String suffix, {bool lowerFirst = false}) {
  if (bytes < base) {
    return '$bytes $suffix';
  }
  var value = bytes / base;
  var unit = 1;
  while (unit < _units.length - 1 && _roundToTenth(value) >= base) {
    value /= base;
    unit++;
  }
  final letter = lowerFirst && unit == 1 ? _units[unit].toLowerCase() : _units[unit];
  return '${_roundToTenth(value).toStringAsFixed(1)} $letter$suffix';
}

/// Размер до последнего байта — с разбивкой по тысячам: `2 147 483 648 B`.
///
/// Для сведений об объекте. Там спрашивают «сколько именно», а не «примерно
/// сколько»: сокращённое `2.0 GB` отвечает на второй вопрос, и по нему нельзя
/// ни сверить два файла, ни сложить.
///
/// Разбивка неразрывными пробелами: длинное число иначе не прочитать, а
/// перенос по нему разорвал бы его пополам.
///
/// Пробел записан кодом нарочно: обычный от неразрывного в исходнике не
/// отличить глазом, и сверять их в тесте пришлось бы наугад.
String formatBytesExact(int bytes) {
  if (bytes < 0) {
    return '';
  }
  return '${_grouped(bytes)}\u00a0B';
}
