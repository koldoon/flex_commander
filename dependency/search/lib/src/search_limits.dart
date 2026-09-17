/// Набранное в полях размера и даты — строками, как набрано, и разобранное.
///
/// Строками, потому что печатают их по букве: `2` по дороге к `2M` — это ещё
/// не число, а `2026-09` по дороге к дате — ещё не дата. Пока человек
/// печатает, негодное значение не ошибка; ошибкой оно становится к `OK`
/// (`docs/spec/file-search.md`, §10.5).
///
/// Значение, а не четыре поля состояния: у полей общая судьба — их разбирают
/// вместе, спрашивают вместе и вместе отдают запросу.
class SearchLimits {
  const SearchLimits({this.sizeFromText = '', this.sizeToText = '', this.afterText = '', this.beforeText = ''});

  final String sizeFromText;
  final String sizeToText;
  final String afterText;
  final String beforeText;

  SearchLimits copyWith({String? sizeFromText, String? sizeToText, String? afterText, String? beforeText}) =>
      SearchLimits(
        sizeFromText: sizeFromText ?? this.sizeFromText,
        sizeToText: sizeToText ?? this.sizeToText,
        afterText: afterText ?? this.afterText,
        beforeText: beforeText ?? this.beforeText,
      );

  int? get sizeFrom => parseSize(sizeFromText);
  int? get sizeTo => parseSize(sizeToText);

  /// «Изменён после» — граница снизу.
  ///
  /// Относительный возраст (`7d`) считается **от сейчас**: «не старше семи
  /// дней» — это и есть «изменён после позавчерашнего четверга».
  DateTime? get changedAfter => parseTime(afterText);
  DateTime? get changedBefore => parseTime(beforeText);

  /// Всё ли набранное разобралось. Пустое поле — не ошибка: это «без
  /// ограничения».
  bool get isValid =>
      _fine(sizeFromText, sizeFrom) &&
      _fine(sizeToText, sizeTo) &&
      _fine(afterText, changedAfter) &&
      _fine(beforeText, changedBefore);

  static bool _fine(String text, Object? value) => text.trim().isEmpty || value != null;

  /// Размер: число с необязательным суффиксом `k`, `M`, `G` (по 1024).
  ///
  /// Суффиксы, а не байты: «два мегабайта» человек и держит в голове
  /// мегабайтами, а `2097152` набирать негде.
  static int? parseSize(String text) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return null;
    }
    final match = RegExp(r'^(\d+)\s*([kKmMgG])?[bB]?$').firstMatch(raw);
    if (match == null) {
      return null;
    }
    final value = int.tryParse(match.group(1)!);
    if (value == null) {
      return null;
    }
    return switch (match.group(2)?.toLowerCase()) {
      'k' => value * 1024,
      'm' => value * 1024 * 1024,
      'g' => value * 1024 * 1024 * 1024,
      _ => value,
    };
  }

  /// Дата `ГГГГ-ММ-ДД` или относительный возраст: `7d`, `2w`, `3m`, `1y`.
  ///
  /// Относительный вид — привычка Total Commander, и он покрывает девять
  /// случаев из десяти, не требуя ни выбиралки дат, ни разбора локальных
  /// форматов. [now] — для проверок: время идёт, а стенд должен быть
  /// повторяемым.
  static DateTime? parseTime(String text, {DateTime? now}) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return null;
    }

    final age = RegExp(r'^(\d+)\s*([dDwWmMyY])$').firstMatch(raw);
    if (age != null) {
      final value = int.tryParse(age.group(1)!);
      if (value == null) {
        return null;
      }
      final from = now ?? DateTime.now();
      return switch (age.group(2)!.toLowerCase()) {
        'd' => from.subtract(Duration(days: value)),
        'w' => from.subtract(Duration(days: value * 7)),
        // Месяц и год — календарём, а не арифметикой суток: «три месяца назад»
        // это то же число тремя месяцами раньше, а не минус девяносто дней.
        'm' => DateTime(from.year, from.month - value, from.day, from.hour, from.minute, from.second),
        _ => DateTime(from.year - value, from.month, from.day, from.hour, from.minute, from.second),
      };
    }

    final date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (date == null) {
      return null;
    }
    final year = int.parse(date.group(1)!);
    final month = int.parse(date.group(2)!);
    final day = int.parse(date.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final parsed = DateTime(year, month, day);
    // `DateTime` переносит лишнее на следующий месяц молча: 31 февраля станет
    // 3 марта. Набранное так — опечатка, а не дата.
    return parsed.month == month && parsed.day == day ? parsed : null;
  }
}
