import 'package:fc_api/fc_api.dart';

/// Что редактор помнит между запусками.
class EditorSettings implements Serializable {
  EditorSettings({this.maxFileSize = defaultMaxFileSize, this.wordWrap = false, this.showLineNumbers = true});

  /// Сто килобайт — как у просмотрщика.
  ///
  /// Правка держит файл в памяти целиком и разбирает его подсветкой, а больший
  /// файл почти наверняка не тот, что правят руками: журнал или выгрузка.
  static const int defaultMaxFileSize = 100 * 1024;

  int maxFileSize;

  bool wordWrap;

  /// Показывать номера строк. В редакторе включены: правя код, на строки
  /// ссылаются — сообщением об ошибке, замечанием в разборе, разговором.
  bool showLineNumbers;

  @override
  void fromMap(Map<String, dynamic> m) {
    maxFileSize = extract(maxFileSize, m['maxFileSize']);
    wordWrap = extract(wordWrap, m['wordWrap']);
    showLineNumbers = extract(showLineNumbers, m['showLineNumbers']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['maxFileSize'] = maxFileSize;
    m['wordWrap'] = wordWrap;
    m['showLineNumbers'] = showLineNumbers;
  }
}
