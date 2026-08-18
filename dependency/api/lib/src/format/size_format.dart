const List<String> _units = ['', 'K', 'M', 'G', 'T', 'P'];

/// Размер для колонки панели: `126`, `6K`, `90.1K`, `14.9M`, `999.9G`.
///
/// Основание 1024; байты — без суффикса и дробной части, дальше один знак после
/// запятой, но незначащий ноль не печатается, как в макете.
/// Отрицательный размер ([FsNode.unknownSize]) даёт пустую строку: у каталогов
/// и псевдоузла «..» размера нет.
String formatSize(int bytes) {
  if (bytes < 0) {
    return '';
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

  return '${_trimZero(_roundToTenth(value))}${_units[unit]}';
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

String _trimZero(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
