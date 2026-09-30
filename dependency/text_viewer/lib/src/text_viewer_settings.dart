import 'package:fc_api/fc_api.dart';

/// Что просмотрщик помнит между запусками.
class TextViewerSettings implements Serializable {
  TextViewerSettings({
    this.maxFileSize = defaultMaxFileSize,
    this.maxFormatSize = defaultMaxFormatSize,
    this.wordWrap = false,
    this.showLineNumbers = false,
  });

  /// Сто килобайт.
  ///
  /// Предел нужен не из-за памяти, а из-за разбора: подсветка читает текст
  /// целиком, а показывать журнал на сто мегабайт просмотрщику всё равно
  /// нечем — для этого нужен другой показ, с чтением по кускам.
  static const int defaultMaxFileSize = 100 * 1024;

  /// Два мегабайта.
  ///
  /// Больше предела открытия нарочно: тот стоит из-за подсветки и его поднимают
  /// руками, а этот — про паузу от разбора. Форматирование идёт на стороне
  /// интерфейса и без отдельного изолята: нажатие `F5` — намеренное действие, и
  /// десяток миллисекунд на мегабайте в нём незаметен, а замершее окно на сотне
  /// мегабайт заметно сразу (`docs/spec/formatters.md`, §9).
  static const int defaultMaxFormatSize = 2 * 1024 * 1024;

  /// Файл больше этого размера просмотрщик не открывает.
  int maxFileSize;

  /// Файл больше этого размера не форматируется: `F5` скажет почему.
  int maxFormatSize;

  /// Переносить длинные строки.
  bool wordWrap;

  /// Показывать номера строк.
  ///
  /// По умолчанию выключены: просмотрщик чаще открывают, чтобы прочитать, а не
  /// чтобы сослаться на строку. В редакторе — наоборот.
  bool showLineNumbers;

  @override
  void fromMap(Map<String, dynamic> m) {
    maxFileSize = extract(maxFileSize, m['maxFileSize']);
    maxFormatSize = extract(maxFormatSize, m['maxFormatSize']);
    wordWrap = extract(wordWrap, m['wordWrap']);
    showLineNumbers = extract(showLineNumbers, m['showLineNumbers']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['maxFileSize'] = maxFileSize;
    m['maxFormatSize'] = maxFormatSize;
    m['wordWrap'] = wordWrap;
    m['showLineNumbers'] = showLineNumbers;
  }
}
