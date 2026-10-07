import 'dart:convert';
import 'dart:math' as math;

import 'encoding_tables.dart';

/// Кодировка текстового файла (`docs/spec/text-encodings.md`).
///
/// Чистый Dart, без Flutter: пишет файл ядро, и кодирует оно же.
enum TextEncoding {
  utf8('UTF-8'),
  utf16le('UTF-16 LE'),
  utf16be('UTF-16 BE'),
  windows1251('Windows-1251'),
  koi8r('KOI8-R'),
  koi8u('KOI8-U'),
  cp866('CP866'),
  macCyrillic('Mac Cyrillic'),
  iso88595('ISO-8859-5'),
  windows1252('Windows-1252');

  const TextEncoding(this.label);

  /// Имя в окне выбора и на плашке пути.
  final String label;

  /// Юникод — сохраняется без вопроса «в чём» (§5).
  bool get isUnicode => this == utf8 || this == utf16le || this == utf16be;

  /// Кириллические однобайтовые — кандидаты определения, в порядке
  /// предпочтения при равной оценке (§3).
  static const List<TextEncoding> cyrillic = [windows1251, koi8r, koi8u, cp866, macCyrillic, iso88595];

  /// По имени (`name`); null — такой нет.
  static TextEncoding? named(String name) {
    for (final encoding in values) {
      if (encoding.name == name) {
        return encoding;
      }
    }
    return null;
  }

  /// Метка порядка байтов этой кодировки; пусто — у неё метки не бывает.
  List<int> get bom => switch (this) {
    utf8 => const [0xEF, 0xBB, 0xBF],
    utf16le => const [0xFF, 0xFE],
    utf16be => const [0xFE, 0xFF],
    _ => const [],
  };

  /// Знаки для байтов `0x80–0xFF`; null — кодировка не однобайтовая.
  String? get _upper => encodingTables[name];

  /// Байты в текст. [strict] — отказ `FormatException` на том, чего в
  /// кодировке нет; иначе там встаёт знак замены. Метку не снимает: это дело
  /// [EncodedText.read].
  String decode(List<int> bytes, {bool strict = false}) {
    switch (this) {
      case utf8:
        return strict ? const Utf8Decoder().convert(bytes) : const Utf8Decoder(allowMalformed: true).convert(bytes);
      case utf16le:
      case utf16be:
        if (bytes.length.isOdd && strict) {
          throw const FormatException('Odd number of bytes in UTF-16');
        }
        final units = List<int>.generate(bytes.length ~/ 2, (i) {
          final a = bytes[i * 2];
          final b = bytes[i * 2 + 1];
          return this == utf16le ? a | (b << 8) : (a << 8) | b;
        });
        return String.fromCharCodes(units);
      default:
        final upper = _upper!;
        final out = StringBuffer();
        for (final byte in bytes) {
          if (byte < 0x80) {
            out.writeCharCode(byte);
            continue;
          }
          final char = upper.codeUnitAt(byte - 0x80);
          if (char == 0xFFFF) {
            if (strict) {
              throw FormatException('Byte 0x${byte.toRadixString(16)} is not defined in $label');
            }
            out.writeCharCode(0xFFFD);
            continue;
          }
          out.writeCharCode(char);
        }
        return out.toString();
    }
  }

  /// Где в [text] первый знак, которого в кодировке нет; null — помещается всё.
  int? unencodable(String text) {
    if (isUnicode) {
      return null;
    }
    final reverse = _reverse;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit < 0x80 || reverse.containsKey(unit)) {
        continue;
      }
      return i;
    }
    return null;
  }

  /// Текст в байты; не помещается — `FormatException` (спрашивать заранее —
  /// [unencodable]).
  List<int> encode(String text) {
    switch (this) {
      case utf8:
        return const Utf8Encoder().convert(text);
      case utf16le:
      case utf16be:
        final out = <int>[];
        for (final unit in text.codeUnits) {
          if (this == utf16le) {
            out
              ..add(unit & 0xFF)
              ..add(unit >> 8);
          } else {
            out
              ..add(unit >> 8)
              ..add(unit & 0xFF);
          }
        }
        return out;
      default:
        final reverse = _reverse;
        final out = List<int>.filled(text.length, 0);
        for (var i = 0; i < text.length; i++) {
          final unit = text.codeUnitAt(i);
          final byte = unit < 0x80 ? unit : reverse[unit];
          if (byte == null) {
            throw FormatException('“${String.fromCharCode(unit)}” does not fit in $label', text, i);
          }
          out[i] = byte;
        }
        return out;
    }
  }

  /// Знак → байт для однобайтовых, считается один раз на кодировку.
  Map<int, int> get _reverse =>
      _reverses[this] ??= {
        for (var i = 0; i < 128; i++)
          if (_upper!.codeUnitAt(i) != 0xFFFF) _upper!.codeUnitAt(i): 0x80 + i,
      };

  static final Map<TextEncoding, Map<int, int>> _reverses = {};

  /// Сколько начала файла смотреть, определяя кодировку (§3).
  static const int sampleSize = 64 * 1024;

  /// Какая это кодировка — по метке, по правильности UTF-8 и по частотам
  /// русских букв (§3). null — строго не читается ни одна: так выглядит
  /// двоичное.
  static TextEncoding? detect(List<int> bytes) {
    final marked = _marked(bytes);
    if (marked != null) {
      return marked;
    }
    final sample = bytes.length > sampleSize ? bytes.sublist(0, sampleSize) : bytes;
    if (_isUtf8(sample, truncated: bytes.length > sampleSize)) {
      return utf8;
    }

    TextEncoding? best;
    var bestScore = 0.0;
    var anyReads = false;
    for (final candidate in cyrillic) {
      final String text;
      try {
        text = candidate.decode(sample, strict: true);
      } on FormatException {
        continue;
      }
      anyReads = true;
      final score = _cyrillicScore(text);
      if (best == null || score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    if (best != null && bestScore > 0) {
      return best;
    }
    // Ни одной правдоподобной кириллицы — западный текст.
    try {
      windows1252.decode(sample, strict: true);
      return windows1252;
    } on FormatException {
      return anyReads ? best : null;
    }
  }

  /// Кодировка по метке порядка байтов; null — метки нет.
  static TextEncoding? _marked(List<int> bytes) {
    for (final encoding in const [utf8, utf16le, utf16be]) {
      final bom = encoding.bom;
      if (bytes.length >= bom.length && _startsWith(bytes, bom)) {
        return encoding;
      }
    }
    return null;
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  /// Правильный ли это UTF-8. Обрезанное начало вправе кончаться на середине
  /// знака — до трёх байт хвоста прощаются.
  static bool _isUtf8(List<int> bytes, {required bool truncated}) {
    for (var cut = 0; cut <= (truncated ? 3 : 0) && cut <= bytes.length; cut++) {
      try {
        const Utf8Decoder().convert(bytes, 0, bytes.length - cut);
        return true;
      } on FormatException {
        continue;
      }
    }
    return false;
  }

  /// Насколько текст похож на русский или украинский (§3).
  ///
  /// Строчная буква весит свою частоту, прописная — десятую часть: в верной
  /// кодировке текст из строчных частых букв, а неверная переставляет регистр
  /// и редкие буквы. Знак верхней половины рядом с латинской буквой —
  /// неверная кодировка западного текста («cafй»); псевдографика и рамки —
  /// неверная кодировка вообще.
  static double _cyrillicScore(String text) {
    var score = 0.0;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit < 0x80) {
        continue;
      }
      final lower = String.fromCharCode(unit).toLowerCase();
      final weight = _frequency[lower];
      if (weight == null) {
        if (unit >= 0x2500 && unit <= 0x259F || unit >= 0x80 && unit <= 0x9F) {
          score -= 20;
        }
        continue;
      }
      if (_isLatin(text, i - 1) || _isLatin(text, i + 1)) {
        score -= 50;
        continue;
      }
      score += lower.codeUnitAt(0) == unit ? weight : weight / 10;
    }
    return score;
  }

  static bool _isLatin(String text, int at) {
    if (at < 0 || at >= text.length) {
      return false;
    }
    final unit = text.codeUnitAt(at);
    return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
  }

  /// Частоты букв на тысячу. Украинские — со своими частотами: без них
  /// KOI8-U не отличить от KOI8-R.
  static const Map<String, double> _frequency = {
    'о': 110, 'е': 85, 'а': 80, 'и': 73, 'н': 67, 'т': 63, 'с': 55, 'р': 47, 'в': 45, 'л': 44, //
    'к': 35, 'м': 32, 'д': 30, 'п': 28, 'у': 26, 'я': 20, 'ы': 19, 'ь': 17, 'г': 17, 'з': 16, //
    'б': 16, 'ч': 14, 'й': 12, 'х': 10, 'ж': 9, 'ш': 7, 'ю': 6, 'ц': 5, 'щ': 4, 'э': 3, //
    'ф': 2, 'ё': 1, 'ъ': 0.4, 'і': 30, 'ї': 5, 'є': 5, 'ґ': 1, 'ў': 1, //
  };
}

/// Текст файла вместе с тем, как он записан: кодировкой и меткой.
class EncodedText {
  const EncodedText(this.text, this.encoding, {this.bom = false});

  final String text;
  final TextEncoding encoding;

  /// Была ли в начале метка порядка байтов — запись вернёт её на место.
  final bool bom;

  /// Прочесть байты файла: в названной кодировке или в определённой (§3).
  ///
  /// [strict] — для правки: null, если строго не читается, иначе байты
  /// испортятся при записи. Без него — для показа: дыры становятся знаками
  /// замены, а не прочтённое ничем читается как Windows-1252.
  static EncodedText? read(List<int> bytes, {TextEncoding? as, bool strict = false}) {
    final encoding = as ?? TextEncoding.detect(bytes) ?? (strict ? null : TextEncoding.windows1252);
    if (encoding == null) {
      return null;
    }
    final bom =
        encoding.bom.isNotEmpty && bytes.length >= encoding.bom.length && TextEncoding._startsWith(bytes, encoding.bom);
    final body = bom ? bytes.sublist(encoding.bom.length) : bytes;
    try {
      return EncodedText(encoding.decode(body, strict: strict), encoding, bom: bom);
    } on FormatException {
      return null;
    }
  }

  /// Байты для записи — с меткой, если она была.
  List<int> get bytes => [if (bom) ...encoding.bom, ...encoding.encode(text)];

  /// Тот же текст в другой кодировке.
  EncodedText withEncoding(TextEncoding encoding, {bool bom = false}) => EncodedText(text, encoding, bom: bom);
}

/// Номер строки (с единицы) знака под [index].
int lineOfIndex(String text, int index) {
  var line = 1;
  for (var i = 0; i < math.min(index, text.length); i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      line++;
    }
  }
  return line;
}
