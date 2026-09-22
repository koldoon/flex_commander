/// Подпись роли выводится из её имени: `windowBackground` → «Window
/// background».
///
/// А не пишется руками: полторы сотни подписей означали бы полторы сотни строк
/// перевода, которые никто не прочитает. Имя роли — это и есть то, чем её
/// называют в коде, и по нему же её ищут (`docs/spec/theme-editor.md`, §4).
String roleTitle(String name) {
  final words = StringBuffer();
  for (var at = 0; at < name.length; at++) {
    final char = name[at];
    final upper = char.toUpperCase() == char && char.toLowerCase() != char;
    final digit = char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;
    final previous = at == 0 ? '' : name[at - 1];
    final previousDigit = previous.isNotEmpty && previous.codeUnitAt(0) >= 0x30 && previous.codeUnitAt(0) <= 0x39;

    // Слово начинается с заглавной или с первой цифры подряд: `terminalAnsi12`
    // — это «Terminal ansi 12», а не «Terminal ansi 1 2».
    if (at > 0 && (upper || (digit && !previousDigit))) {
      words.write(' ');
    }
    words.write(at == 0 ? char.toUpperCase() : char.toLowerCase());
  }
  return words.toString();
}
