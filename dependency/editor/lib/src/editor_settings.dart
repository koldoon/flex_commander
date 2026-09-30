import 'package:fc_api/fc_api.dart';

/// Что редактор помнит между запусками.
class EditorSettings implements Serializable {
  EditorSettings({
    this.maxFileSize = defaultMaxFileSize,
    this.maxFormatSize = defaultMaxFormatSize,
    this.wordWrap = false,
    this.showLineNumbers = true,
  });

  /// Сто килобайт — как у просмотрщика.
  ///
  /// Правка держит файл в памяти целиком и разбирает его подсветкой, а больший
  /// файл почти наверняка не тот, что правят руками: журнал или выгрузка.
  static const int defaultMaxFileSize = 100 * 1024;

  /// Два мегабайта — как в показе текста.
  ///
  /// Больше предела открытия нарочно: тот стоит из-за подсветки и его поднимают
  /// руками, а этот — про паузу от разбора. Форматирование идёт на стороне
  /// интерфейса и без отдельного изолята (`docs/spec/formatters.md`, §9).
  static const int defaultMaxFormatSize = 2 * 1024 * 1024;

  int maxFileSize;

  /// Документ больше этого размера не форматируется: `Alt-Shift-F` скажет
  /// почему.
  int maxFormatSize;

  bool wordWrap;

  /// Показывать номера строк. В редакторе включены: правя код, на строки
  /// ссылаются — сообщением об ошибке, замечанием в разборе, разговором.
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
