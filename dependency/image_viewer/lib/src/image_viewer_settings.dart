import 'package:fc_api/fc_api.dart';

/// Что просмотрщик изображений помнит между запусками.
class ImageViewerSettings implements Serializable {
  ImageViewerSettings({
    this.maxFileSize = defaultMaxFileSize,
    this.maxPixels = defaultMaxPixels,
    this.fitToWindow = true,
  });

  /// Шестьдесят четыре мегабайта.
  static const int defaultMaxFileSize = 64 * 1024 * 1024;

  /// Шестьдесят четыре мегапикселя — примерно 8000×8000.
  ///
  /// Второй предел нужен потому, что первый ничего не говорит о памяти:
  /// картинка сжата, а разворачивается в четыре байта на точку. Пять мегабайт
  /// png бывают двадцатью тысячами точек по стороне — это полтора гигабайта, и
  /// умирает приложение молча.
  static const int defaultMaxPixels = 64 * 1000 * 1000;

  /// Файл больше этого размера просмотрщик не открывает.
  int maxFileSize;

  /// Точек больше этого числа он не распаковывает.
  int maxPixels;

  /// Вписывать картинку в окно. Иначе — точка в точку.
  bool fitToWindow;

  @override
  void fromMap(Map<String, dynamic> m) {
    maxFileSize = extract(maxFileSize, m['maxFileSize']);
    maxPixels = extract(maxPixels, m['maxPixels']);
    fitToWindow = extract(fitToWindow, m['fitToWindow']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['maxFileSize'] = maxFileSize;
    m['maxPixels'] = maxPixels;
    m['fitToWindow'] = fitToWindow;
  }
}
