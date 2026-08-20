import 'dart:convert';

import 'package:fc_api/fc_api.dart';

/// Каким переводом строки написан файл.
///
/// Помнить обязательно: разбор приводит всё к `\n`, и сохранение без этой
/// памяти молча превратило бы windows-файл в unix. Такую правку человек не
/// заказывал и заметит её не сразу — по чужому diff'у на весь файл.
enum LineBreak {
  lf('\n'),
  crlf('\r\n'),
  cr('\r');

  const LineBreak(this.text);

  final String text;

  /// Какой перевод в этом тексте: смотрим первый встреченный.
  ///
  /// Первый, а не большинство: смешанные файлы бывают, и «исправлять» их
  /// молча — то же самое самоуправство.
  static LineBreak detect(String text) {
    final index = text.indexOf('\n');
    if (index < 0) {
      return text.contains('\r') ? cr : lf;
    }
    return index > 0 && text.codeUnitAt(index - 1) == 0x0D ? crlf : lf;
  }
}

/// Текстовый файл, открытый на правку.
class TextFile {
  const TextFile({required this.text, required this.lineBreak});

  /// Содержимое с переводами строк, приведёнными к `\n`.
  final String text;

  /// Каким переводом строки файл был записан.
  final LineBreak lineBreak;

  /// Содержимое в том виде, в каком его надо записать обратно.
  String get bytes => lineBreak == LineBreak.lf ? text : text.replaceAll('\n', lineBreak.text);

  /// Читает файл, отказываясь от того, что правкой испортишь.
  ///
  /// Кодировка проверяется **строго**, в отличие от просмотрщика: тот заменяет
  /// битые байты знаком замены, и это честно — он показывает. Сохранить такой
  /// текст обратно значило бы записать знаки замены вместо исходных байтов, то
  /// есть испортить файл молча.
  static Future<TextFile> read(FsNode node, FileContentProvider source) async {
    final bytes = <int>[];
    await for (final chunk in await source.openRead(node)) {
      bytes.addAll(chunk);
    }

    final String decoded;
    try {
      decoded = utf8.decode(bytes);
    } on FormatException {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }

    return TextFile(
      text: decoded.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      lineBreak: LineBreak.detect(decoded),
    );
  }
}
