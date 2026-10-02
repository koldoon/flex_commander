import 'package:fc_api/fc_api.dart';

/// Что просмотрщик PDF помнит между запусками.
class PdfViewerSettings implements Serializable {
  PdfViewerSettings({this.maxFileSize = defaultMaxFileSize, this.wholePage = false});

  /// Двести пятьдесят шесть мегабайт.
  ///
  /// Файл читается целиком — системе нужны все байты, — и предел бережёт
  /// память от случайного `F3` на гигабайтном скане (`docs/spec/pdf-viewer.md`,
  /// §4).
  static const int defaultMaxFileSize = 256 * 1024 * 1024;

  /// Файл больше этого размера просмотрщик не открывает.
  int maxFileSize;

  /// Вписывать страницу целиком. Иначе — по ширине окна.
  bool wholePage;

  @override
  void fromMap(Map<String, dynamic> m) {
    maxFileSize = extract(maxFileSize, m['maxFileSize']);
    wholePage = extract(wholePage, m['wholePage']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['maxFileSize'] = maxFileSize;
    m['wholePage'] = wholePage;
  }
}
