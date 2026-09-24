/// Замена в имени: «найти → заменить», буквально или выражением.
///
/// Соседнее значение к [NameRule], а не его третий режим: тот в режиме маски
/// сличает имя **целиком** (`*.dart`), а здесь ищут **подстроку**, и смешать
/// это значило бы сломать поиск, которому он служит
/// (`docs/spec/multi-rename.md`, §7).
class NameReplacement {
  const NameReplacement._(this.find, this.replace, this.regexp, this.caseSensitive, this._pattern);

  /// Разобрать набранное.
  ///
  /// **Не бросает**: неверное выражение просто даёт негодную замену
  /// ([isValid] == false), а окно показывает это у поля — тем же приёмом, что
  /// `NameRule.parse`.
  factory NameReplacement.parse(String find, String replace, {bool regexp = false, bool caseSensitive = false}) {
    if (find.isEmpty) {
      return NameReplacement._(find, replace, regexp, caseSensitive, null);
    }
    final source = regexp ? find : RegExp.escape(find);
    RegExp? pattern;
    try {
      pattern = RegExp(source, caseSensitive: caseSensitive);
    } on FormatException {
      pattern = null;
    }
    return NameReplacement._(find, replace, regexp, caseSensitive, pattern);
  }

  /// Что набрано — как набрано: эти же строки возвращаются в поля и уходят в
  /// сохранённый набор.
  final String find;
  final String replace;

  /// Читать «найти» выражением. В замене тогда работают группы (`$1`…`$9`).
  final bool regexp;

  /// Различать ли регистр. По умолчанию нет — тот же довод, что у масок: на
  /// macOS его не различает и файловая система.
  final bool caseSensitive;

  final RegExp? _pattern;

  /// Задана ли замена вовсе. Пустое «найти» — правила нет.
  bool get isEmpty => find.isEmpty;

  /// Собралось ли выражение. У буквальной замены собираться нечему.
  bool get isValid => find.isEmpty || _pattern != null;

  /// Заменить **все** вхождения, как в MRT.
  String apply(String name) {
    final pattern = _pattern;
    if (pattern == null) {
      return name;
    }
    return name.replaceAllMapped(pattern, (match) => _substituted(match));
  }

  /// Подставляет группы в замену: `$1`…`$9` и `$$` для самого доллара.
  ///
  /// Руками, а не `replaceAll` по строке замены: у буквальной замены `$1` — это
  /// текст `$1`, и превращать его в группу значило бы удивлять того, кто про
  /// выражения не просил.
  String _substituted(Match match) {
    if (!regexp) {
      return replace;
    }
    final out = StringBuffer();
    for (var at = 0; at < replace.length; at++) {
      final char = replace[at];
      if (char != r'$' || at + 1 >= replace.length) {
        out.write(char);
        continue;
      }
      final next = replace[at + 1];
      if (next == r'$') {
        out.write(r'$');
        at++;
        continue;
      }
      final group = int.tryParse(next);
      if (group == null || group > match.groupCount) {
        out.write(char);
        continue;
      }
      out.write(match.group(group) ?? '');
      at++;
    }
    return out.toString();
  }

  @override
  String toString() => 'NameReplacement("$find" → "$replace"${regexp ? ', выражением' : ''})';
}

/// Что сделать с регистром имени.
///
/// Свой список у имени и свой у расширения: один заставлял бы выбирать между
/// `ОТЧЁТ.PDF` и ничем, а самое частое желание — `.JPG` → `.jpg`, не трогая
/// имени (`docs/spec/multi-rename.md`, §6).
enum RenameCase {
  keep,
  upper,
  lower,

  /// Первая буква заглавная, остальные строчные.
  sentence,

  /// Каждое Слово с заглавной: слова делят пробелы, `_`, `-` и точки.
  words;

  String apply(String text) => switch (this) {
    RenameCase.keep => text,
    RenameCase.upper => text.toUpperCase(),
    RenameCase.lower => text.toLowerCase(),
    RenameCase.sentence => _sentence(text),
    RenameCase.words => _words(text),
  };

  static String _sentence(String text) {
    if (text.isEmpty) {
      return text;
    }
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  static String _words(String text) {
    final out = StringBuffer();
    var starts = true;
    for (final char in text.split('')) {
      if (_breaks.contains(char)) {
        starts = true;
        out.write(char);
        continue;
      }
      out.write(starts ? char.toUpperCase() : char.toLowerCase());
      starts = false;
    }
    return out.toString();
  }

  static const Set<String> _breaks = {' ', '_', '-', '.', '(', ')', '[', ']'};
}
