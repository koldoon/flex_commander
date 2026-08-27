import 'dart:convert';

import 'package:fc_api/fc_api.dart';

/// Текст файла, готовый к показу.
///
/// Отдельно от редакторского `TextFile`, и разница между ними существенная:
/// просмотрщик **показывает**, а редактор ещё и пишет. Поэтому здесь чтение с
/// допуском ошибок, а там — строгое.
class TextDocument {
  const TextDocument(this.text);

  /// Приводит переводы строк к одному виду.
  ///
  /// Три вида, потому что файлы приходят с разных машин: `\r\n` (Windows),
  /// `\n` (unix) и одиночный `\r` (старые Mac). Показ знает только про `\n`, и
  /// не приведённый `\r` встал бы в тексте видимым мусором.
  ///
  /// Обратно их возвращать не нужно: просмотрщик ничего не записывает.
  factory TextDocument.parse(String text) => TextDocument(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));

  /// Читает файл целиком.
  ///
  /// Целиком, а не потоком: предел размера уже проверен тем, кто вызывает, а
  /// показывать надо и последнюю строку тоже — значит дочитать до конца
  /// придётся в любом случае.
  ///
  /// Кодировка — UTF-8 с допуском ошибок: файл может оказаться и не текстом
  /// вовсе, и падать на этом просмотрщик не должен — испорченные байты
  /// становятся видимыми знаками замены.
  static Future<TextDocument> read(FsNode node, FileContentProvider source) async {
    final bytes = <int>[];
    await for (final chunk in await source.openRead(node)) {
      bytes.addAll(chunk);
    }
    return TextDocument.parse(utf8.decode(bytes, allowMalformed: true));
  }

  final String text;
}
