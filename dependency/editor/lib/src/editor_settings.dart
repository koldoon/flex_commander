import 'package:fc_api/fc_api.dart';

/// Что редактор помнит между запусками.
class EditorSettings implements Serializable {
  EditorSettings({this.maxFileSize = defaultMaxFileSize, this.wordWrap = false});

  /// Сто килобайт — как у просмотрщика.
  ///
  /// Правка держит файл в памяти целиком и разбирает его подсветкой, а больший
  /// файл почти наверняка не тот, что правят руками: журнал или выгрузка.
  static const int defaultMaxFileSize = 100 * 1024;

  int maxFileSize;

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
