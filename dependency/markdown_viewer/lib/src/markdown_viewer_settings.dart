import 'package:fc_api/fc_api.dart';

/// Что просмотрщик markdown помнит между запусками.
class MarkdownViewerSettings implements Serializable {
  MarkdownViewerSettings({this.maxFileSize = defaultMaxFileSize, this.startFormatted = true});

  /// Полмегабайта.
  ///
  /// Больше, чем у текста (сто килобайт): текстовый предел стоит из-за
  /// подсветки, а здесь документ строится **лениво**, по блоку на экран
  /// (`docs/spec/markdown-viewer.md`, §5). Полмегабайта покрывает и `README`, и
  /// длинные спецификации — `docs/roadmap.md` этого проекта весит треть.
  static const int defaultMaxFileSize = 512 * 1024;

  /// Файл больше этого размера просмотрщик не открывает.
  int maxFileSize;

  /// Открывать свёрстанным. Иначе — сразу исходником.
  ///
  /// По умолчанию свёрстанным: `.md` открывают, чтобы прочитать; правят его в
  /// редакторе, а не в просмотрщике.
  bool startFormatted;

  @override
  void fromMap(Map<String, dynamic> m) {
    maxFileSize = extract(maxFileSize, m['maxFileSize']);
    startFormatted = extract(startFormatted, m['startFormatted']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['maxFileSize'] = maxFileSize;
    m['startFormatted'] = startFormatted;
  }
}
