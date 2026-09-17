import 'dart:convert';

/// Что ищем **внутри** файла.
///
/// Байтовыми образцами, а не разобранным текстом: тогда кодировку файла не надо
/// угадывать — набранное превращается в байты нескольких кодировок, и файл
/// читается один раз (`docs/spec/file-search.md`, §11.4).
///
/// Выражение — исключение: оно ищет по тексту, разобранному как UTF-8, и с
/// «любыми кодировками» не сочетается.
class ContentRule {
  ContentRule._(
    this.text,
    this.regexp,
    this.caseSensitive,
    this.wholeWords,
    this.anyCharset,
    this._patterns,
    this._pattern,
  );

  /// Разобрать набранное.
  ///
  /// [allCharsets] — искать не только в UTF-8: добавляются CP1251, KOI8-R и
  /// Latin-1. Образцы, совпавшие побайтно (латиница везде одна и та же), в
  /// набор не дублируются.
  factory ContentRule.parse(
    String text, {
    bool regexp = false,
    bool caseSensitive = false,
    bool wholeWords = false,
    bool allCharsets = false,
  }) {
    if (text.isEmpty) {
      return ContentRule._(text, regexp, caseSensitive, wholeWords, allCharsets, const [], null);
    }

    if (regexp) {
      RegExp? pattern;
      try {
        pattern = RegExp(text, caseSensitive: caseSensitive);
      } on FormatException {
        pattern = null;
      }
      return ContentRule._(text, true, caseSensitive, wholeWords, false, const [], pattern);
    }

    final encodings = allCharsets ? _Encoding.values : const [_Encoding.utf8];
    final patterns = <_BytePattern>[];
    for (final encoding in encodings) {
      final pattern = _BytePattern.of(text, encoding, caseSensitive: caseSensitive);
      // Кодировка, которой этот текст не записать (кириллица в Latin-1),
      // образца не даёт — и это не ошибка, а «здесь искать нечего».
      if (pattern == null || patterns.any((known) => known.sameAs(pattern))) {
        continue;
      }
      patterns.add(pattern);
    }
    return ContentRule._(text, false, caseSensitive, wholeWords, allCharsets, patterns, null);
  }

  /// Правило, не ищущее ничего.
  static final ContentRule none = ContentRule.parse('');

  /// Что набрал человек — как набрал.
  final String text;

  final bool regexp;
  final bool caseSensitive;
  final bool wholeWords;

  /// Ищем не только в UTF-8.
  ///
  /// От этого зависит и то, что считать двоичным: текст в CP1251 как UTF-8 не
  /// разбирается вовсе, и обычное сито отсеяло бы его целиком — вместе с теми
  /// файлами, ради которых флажок и включают (§11.2). Значением, а не выводом
  /// из набора образцов: у латинского слова образец во всех кодировках один и
  /// тот же, а искать его просили всё равно везде.
  final bool anyCharset;

  final List<_BytePattern> _patterns;
  final RegExp? _pattern;

  /// Задано ли правило вовсе.
  bool get isEmpty => text.isEmpty;

  /// Собралось ли выражение. У строки собираться нечему.
  bool get isValid => !regexp || text.isEmpty || _pattern != null;

  /// Сколько байт переносить из куска в кусок.
  ///
  /// Совпадение обязано находиться **на стыке**: без хвоста поиск молча
  /// пропускает то, что разорвано границей чтения, — а «молча» тут и есть
  /// худшее (§11.3).
  int get tail {
    var most = 0;
    for (final pattern in _patterns) {
      if (pattern.length > most) {
        most = pattern.length;
      }
    }
    return most == 0 ? 0 : most - 1;
  }

  /// Есть ли совпадение в этом куске байт.
  bool matchesBytes(List<int> bytes, {int from = 0}) {
    for (final pattern in _patterns) {
      if (pattern.findIn(bytes, from: from, wholeWords: wholeWords)) {
        return true;
      }
    }
    return false;
  }

  /// Есть ли совпадение в этой строке текста — для выражения.
  bool matchesText(String line) {
    final pattern = _pattern;
    if (pattern == null) {
      return false;
    }
    if (!wholeWords) {
      return pattern.hasMatch(line);
    }
    for (final match in pattern.allMatches(line)) {
      if (_wordBoundary(line, match.start, match.end)) {
        return true;
      }
    }
    return false;
  }

  static bool _wordBoundary(String line, int start, int end) {
    final before = start == 0 ? null : line.codeUnitAt(start - 1);
    final after = end >= line.length ? null : line.codeUnitAt(end);
    return !_isWordChar(before) && !_isWordChar(after);
  }

  static bool _isWordChar(int? code) {
    if (code == null) {
      return false;
    }
    // Буква, цифра, подчёркивание — и всё, что за латиницей: в любой из наших
    // кодировок это буква (§11.4).
    return code >= 0x80 ||
        (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5a) ||
        (code >= 0x61 && code <= 0x7a) ||
        code == 0x5f;
  }
}

/// Кодировки, в которых ищем.
enum _Encoding { utf8, cp1251, koi8r, latin1 }

/// Образец в байтах одной кодировки: знак за знаком.
///
/// Каждый знак — набор допустимых байтовых форм: строчная и прописная. Длины
/// форм внутри одной кодировки совпадают (латиница — байт, кириллица в UTF-8 —
/// два), поэтому у образца есть общая длина, а сличение остаётся прямым.
class _BytePattern {
  _BytePattern(this._chars, this.length);

  static _BytePattern? of(String text, _Encoding encoding, {required bool caseSensitive}) {
    final chars = <List<List<int>>>[];
    var length = 0;
    for (final rune in text.runes) {
      final forms = <List<int>>[];
      for (final variant in _variantsOf(rune, caseSensitive: caseSensitive)) {
        final bytes = _encode(variant, encoding);
        if (bytes == null) {
          return null;
        }
        if (!forms.any((known) => _same(known, bytes))) {
          forms.add(bytes);
        }
      }
      // Формы разной длины (такое бывает у редких знаков) не сличить прямым
      // ходом — берём только первую: лучше искать точнее, чем шире.
      forms.removeWhere((bytes) => bytes.length != forms.first.length);
      chars.add(forms);
      length += forms.first.length;
    }
    return chars.isEmpty ? null : _BytePattern(chars, length);
  }

  final List<List<List<int>>> _chars;

  /// Общая длина совпадения в байтах.
  final int length;

  bool sameAs(_BytePattern other) {
    if (_chars.length != other._chars.length || length != other.length) {
      return false;
    }
    for (var at = 0; at < _chars.length; at++) {
      final mine = _chars[at];
      final theirs = other._chars[at];
      if (mine.length != theirs.length) {
        return false;
      }
      for (var form = 0; form < mine.length; form++) {
        if (!_same(mine[form], theirs[form])) {
          return false;
        }
      }
    }
    return true;
  }

  /// Ищет образец начиная с [from]; [wholeWords] — проверяя соседние байты.
  bool findIn(List<int> bytes, {required int from, required bool wholeWords}) {
    for (var at = from; at + length <= bytes.length; at++) {
      if (!_matchesAt(bytes, at)) {
        continue;
      }
      if (!wholeWords || _standsAlone(bytes, at)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesAt(List<int> bytes, int at) {
    var offset = at;
    for (final forms in _chars) {
      var matched = false;
      for (final form in forms) {
        if (_hasAt(bytes, offset, form)) {
          offset += form.length;
          matched = true;
          break;
        }
      }
      if (!matched) {
        return false;
      }
    }
    return true;
  }

  bool _standsAlone(List<int> bytes, int at) {
    final before = at == 0 ? null : bytes[at - 1];
    final after = at + length >= bytes.length ? null : bytes[at + length];
    return !_isWordByte(before) && !_isWordByte(after);
  }

  static bool _isWordByte(int? byte) {
    if (byte == null) {
      return false;
    }
    return byte >= 0x80 ||
        (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        byte == 0x5f;
  }

  static bool _hasAt(List<int> bytes, int at, List<int> form) {
    if (at + form.length > bytes.length) {
      return false;
    }
    for (var i = 0; i < form.length; i++) {
      if (bytes[at + i] != form[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Знак и его вторая форма: строчная и прописная.
Iterable<int> _variantsOf(int rune, {required bool caseSensitive}) {
  if (caseSensitive) {
    return [rune];
  }
  final char = String.fromCharCode(rune);
  final lower = char.toLowerCase();
  final upper = char.toUpperCase();
  // Многознаковые формы (ß → SS) не берём: одна буква обязана оставаться одной.
  return {rune, if (lower.runes.length == 1) lower.runes.first, if (upper.runes.length == 1) upper.runes.first};
}

/// Байты одного знака в этой кодировке; null — знак в ней не записывается.
List<int>? _encode(int rune, _Encoding encoding) {
  switch (encoding) {
    case _Encoding.utf8:
      return utf8.encode(String.fromCharCode(rune));
    case _Encoding.latin1:
      return rune <= 0xff ? [rune] : null;
    case _Encoding.cp1251:
      return _singleByte(rune, _cp1251);
    case _Encoding.koi8r:
      return _singleByte(rune, _koi8r);
  }
}

List<int>? _singleByte(int rune, Map<int, int> table) {
  if (rune < 0x80) {
    return [rune];
  }
  final byte = table[rune];
  return byte == null ? null : [byte];
}

/// Кириллица в CP1251: две сплошные полосы и две отдельные буквы.
final Map<int, int> _cp1251 = {
  for (var at = 0; at < 32; at++) 0x410 + at: 0xc0 + at,
  for (var at = 0; at < 32; at++) 0x430 + at: 0xe0 + at,
  0x401: 0xa8,
  0x451: 0xb8,
};

/// Кириллица в KOI8-R: порядок букв свой, поэтому таблица выписана целиком.
final Map<int, int> _koi8r = () {
  const lower = 'юабцдефгхийклмнопярстужвьызшэщчъ';
  const upper = 'ЮАБЦДЕФГХИЙКЛМНОПЯРСТУЖВЬЫЗШЭЩЧЪ';
  return <int, int>{
    for (var at = 0; at < lower.length; at++) lower.codeUnitAt(at): 0xc0 + at,
    for (var at = 0; at < upper.length; at++) upper.codeUnitAt(at): 0xe0 + at,
    0x451: 0xa3,
    0x401: 0xb3,
  };
}();
