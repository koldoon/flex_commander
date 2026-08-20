import 'package:fc_api/fc_api.dart';

/// Что просмотрщик помнит между запусками.
class ViewerSettings implements Serializable {
  ViewerSettings({this.maxFileSize = defaultMaxFileSize, this.wordWrap = false});

  /// Сто килобайт.
  ///
  /// Предел нужен не из-за памяти, а из-за разбора: подсветка читает текст
  /// целиком, а показывать журнал на сто мегабайт просмотрщику всё равно
  /// нечем — для этого нужен другой показ, с чтением по кускам.
  static const int defaultMaxFileSize = 100 * 1024;

  /// Файл больше этого размера просмотрщик не открывает.
  int maxFileSize;

  /// Переносить длинные строки.
  bool wordWrap;

  @override
  void fromMap(Map<String, dynamic> m) {
    maxFileSize = extract(maxFileSize, m['maxFileSize']);
    wordWrap = extract(wordWrap, m['wordWrap']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['maxFileSize'] = maxFileSize;
    m['wordWrap'] = wordWrap;
  }
}
