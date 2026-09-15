/// Как показать дату в колонке (`docs/spec/column-formats.md`, §4).
enum DateFormat {
  /// `19-02-2018` — как в макете, и потому умолчание.
  day('date'),

  /// `19-02-2018 14:05`.
  dayTime('datetime'),

  /// `2018-02-19` — сортируемая запись, привычная в списках файлов.
  iso('iso'),

  /// `2018-02-19 14:05`.
  isoTime('isotime');

  const DateFormat(this.id);

  /// Имя формата в раскладке колонки и в настройках.
  final String id;

  /// Формат по имени; незнакомое — умолчание: показать дату надо в любом
  /// случае.
  static DateFormat byId(String id) {
    for (final format in values) {
      if (format.id == id) {
        return format;
      }
    }
    return day;
  }
}

/// Дата для колонок панели: `19-02-2018` или так, как попросили.
String formatDate(DateTime? value, [DateFormat format = DateFormat.day]) {
  if (value == null) {
    return '';
  }
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final date = switch (format) {
    DateFormat.day || DateFormat.dayTime => '$day-$month-${value.year}',
    DateFormat.iso || DateFormat.isoTime => '${value.year}-$month-$day',
  };
  return switch (format) {
    DateFormat.day || DateFormat.iso => date,
    DateFormat.dayTime || DateFormat.isoTime => '$date ${_timeOf(value)}',
  };
}

String _timeOf(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Дата и время для подсказок и диалогов: `19-02-2018 14:05`.
String formatDateTime(DateTime? value) => formatDate(value, DateFormat.dayTime);
