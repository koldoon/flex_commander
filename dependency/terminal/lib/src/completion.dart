/// Последний токен строки, разобранный для дополнения.
///
/// Разбор отделён от всего остального нарочно: это чистая работа со строкой, и
/// проверять её надо без приложения, панели и провайдера — вариантов у неё
/// больше, чем у всего дополнения вместе взятого.
class CompletionToken {
  const CompletionToken({
    required this.start,
    required this.end,
    required this.directory,
    required this.prefix,
    required this.quote,
  });

  /// Границы токена в строке: сюда же вставляется дополненное.
  ///
  /// [start] указывает на начало токена **вместе** с открывающей кавычкой:
  /// заменяется он целиком, а кавычку дописывает тот, кто вставляет.
  final int start;
  final int end;

  /// Каталог, в котором искать; пусто — каталог панели.
  ///
  /// Путь как набрали, без разбора `~`: домашний каталог знает провайдер, а не
  /// разбор строки.
  final String directory;

  /// Начало имени, по которому отбирать.
  final String prefix;

  /// Кавычка, которой токен открыт; пусто — токен без кавычек.
  final String quote;

  /// Токен пуст — строка кончается пробелом или пуста вовсе.
  bool get isEmpty => directory.isEmpty && prefix.isEmpty;

  /// Разбирает строку до курсора.
  ///
  /// Токеном считается всё от последнего **неэкранированного** пробела вне
  /// кавычек до курсора. От курсора, а не от конца строки: поправить середину
  /// команды — обычное дело, и дополнять в этот момент надо то, что под
  /// курсором.
  factory CompletionToken.parse(String line, int cursor) {
    final at = cursor.clamp(0, line.length);
    var start = 0;
    var quote = '';
    var quoteStart = -1;

    for (var i = 0; i < at; i++) {
      final char = line[i];
      if (char == r'\') {
        // Экранированное следом идёт как есть — в том числе пробел.
        i++;
        continue;
      }
      if (quote.isNotEmpty) {
        if (char == quote) {
          quote = '';
          quoteStart = -1;
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
        quoteStart = i;
        continue;
      }
      if (char == ' ' || char == '\t') {
        start = i + 1;
      }
    }

    // Кавычка, открытая внутри токена, началом токена и остаётся: закрыть её
    // придётся при вставке.
    if (quote.isNotEmpty && quoteStart >= start) {
      start = quoteStart;
    }

    final raw = line.substring(start, at);
    final value = _unescape(quote.isEmpty ? raw : raw.substring(1));
    final slash = value.lastIndexOf('/');

    return CompletionToken(
      start: start,
      end: at,
      directory: slash < 0 ? '' : value.substring(0, slash + 1),
      prefix: slash < 0 ? value : value.substring(slash + 1),
      quote: quote,
    );
  }

  /// Снимает экранирование: `my\ file` — это одно имя, а не два.
  static String _unescape(String value) {
    if (!value.contains(r'\')) {
      return value;
    }
    final result = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (value[i] == r'\' && i + 1 < value.length) {
        result.write(value[++i]);
        continue;
      }
      result.write(value[i]);
    }
    return result.toString();
  }

  @override
  String toString() => 'CompletionToken($start..$end, dir=$directory, prefix=$prefix, quote=$quote)';
}

/// Общее начало у всех строк списка; пусто — общего нет.
String commonPrefix(List<String> values) {
  if (values.isEmpty) {
    return '';
  }
  var prefix = values.first;
  for (final value in values.skip(1)) {
    var length = 0;
    while (length < prefix.length && length < value.length && prefix[length] == value[length]) {
      length++;
    }
    prefix = prefix.substring(0, length);
    if (prefix.isEmpty) {
      break;
    }
  }
  return prefix;
}
