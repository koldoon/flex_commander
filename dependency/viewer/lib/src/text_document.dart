import 'dart:convert';

import 'package:fc_api/fc_api.dart';

/// Текст файла, разобранный на строки.
///
/// Строки нужны и показу (рисуется только видимое), и подсветке, и прокрутке
/// по ширине: длину холста даёт самая длинная строка, и считать её каждый раз
/// заново незачем.
class TextDocument {
  TextDocument({required this.lines, required this.longestLine});

  /// Пустой документ: файл на ноль байт — это не ошибка.
  TextDocument.empty() : lines = const [''], longestLine = 0;

  /// Разбирает текст на строки.
  ///
  /// Три вида перевода строки, потому что файлы приходят с разных машин:
  /// `\r\n` (Windows), `\n` (unix) и одиночный `\r` (старые Mac). Завершающий
  /// перевод новой строки не создаёт: в файле, оканчивающемся переводом, строк
  /// столько же, сколько их видит редактор.
  factory TextDocument.parse(String text) {
    if (text.isEmpty) {
      return TextDocument.empty();
    }

    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    if (lines.length > 1 && lines.last.isEmpty) {
      lines.removeLast();
    }

    var longest = 0;
    for (final line in lines) {
      if (line.length > longest) {
        longest = line.length;
      }
    }

    return TextDocument(lines: List.unmodifiable(lines), longestLine: longest);
  }

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

  final List<String> lines;

  /// Длина самой длинной строки в символах.
  final int longestLine;

  int get lineCount => lines.length;
}
