import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_ui_api/fc_ui_api.dart';

import 'content_type_table.dart';

/// Текст или двоичное — когда ни одна сигнатура не совпала.
///
/// Правила и их причины — в `docs/spec/content-types.md` §9. Коротко: BOM
/// решает сразу, нулевой байт означает двоичное, остальное пробуется разобрать
/// как UTF-8.
ContentType textOrBinary(Uint8List head) {
  // UTF-16 узнаётся только по метке и дальше не разбирается: разбирать его
  // здесь нечем, а ответ «текст» уже полный.
  if (_utf16(head)) {
    return ContentTypeTable.text;
  }

  // Нулевого байта в тексте не бывает. Проверка идёт раньше разбора, потому
  // что UTF-8 нулевой байт как раз пропустит: он законный символ.
  if (head.contains(0)) {
    return ContentTypeTable.binary;
  }

  final text = _utf8OrNull(head);
  if (text == null) {
    return ContentTypeTable.binary;
  }
  // Картинка, записанная текстом, — всё-таки картинка: по ней и правило иконки
  // пишется как по картинке. Дальше этого разбор текста не идёт: «на каком
  // языке написан текст» — вопрос к правилам иконок, а не к сигнатурам (§13).
  return _looksLikeSvg(text) ? ContentTypeTable.svg : ContentTypeTable.text;
}

/// UTF-16 — по метке порядка байтов, и только по ней.
///
/// **Без** метки он объявляется двоичным намеренно: он и выглядит как двоичное
/// — половина байтов нулевая, — а угадывать кодировку по перемежающимся нулям
/// значит однажды объявить текстом то, что им не является. Кто хочет прочесть
/// такой файл, откроет его просмотрщиком: строгость про кодировки живёт там.
///
/// Метка UTF-8 (`EF BB BF`) здесь не нужна: файл с ней разбирается обычным
/// путём и приходит к тому же ответу — заодно оставаясь картинкой, если это
/// `svg`.
bool _utf16(Uint8List head) {
  if (head.length < 2) {
    return false;
  }
  final first = head[0];
  final second = head[1];
  return (first == 0xff && second == 0xfe) || (first == 0xfe && second == 0xff);
}

/// Разбор UTF-8 с запасом на обрыв.
///
/// Последний символ куска почти наверняка обрезан границей чтения, и обрывок
/// не повод объявить файл двоичным: хвост из недописанной последовательности
/// отбрасывается — не больше четырёх байт, длиннее символов не бывает.
String? _utf8OrNull(Uint8List head) {
  var end = head.length;
  for (var i = 0; i < 3 && end > 0; i++) {
    final byte = head[end - 1];
    if (byte & 0xc0 != 0x80) {
      // Не продолжение: если это начало последовательности, значит она
      // оборвана и её надо снять целиком.
      if (byte >= 0xc0) {
        end--;
      }
      break;
    }
    end--;
  }
  // Сняли все байты до одного — читать нечего, и это не текст.
  if (end == 0) {
    return null;
  }

  try {
    return utf8.decode(Uint8List.sublistView(head, 0, end));
  } on FormatException {
    return null;
  }
}

bool _looksLikeSvg(String text) {
  final head = text.length > 1024 ? text.substring(0, 1024) : text;
  return head.toLowerCase().contains('<svg');
}
