/// Дата для колонок панели: `19-02-2018`.
///
/// Формат зафиксирован макетом. Когда понадобится настраиваемый формат, эта
/// функция станет полем темы, а не разъедется по виджетам.
String formatDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day-$month-${value.year}';
}

/// Дата и время для подсказок и диалогов: `19-02-2018 14:05`.
String formatDateTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${formatDate(value)} $hour:$minute';
}
