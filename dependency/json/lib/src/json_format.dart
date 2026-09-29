import 'dart:convert';

/// Привести json в читаемый вид.
///
/// Отступ — два пробела, перевод строки `\n`, в конце файла один перевод
/// строки. Настройкой это не делается: вариантов здесь столько же, сколько
/// людей, а согласия между ними нет (`docs/spec/formatters.md`, §7).
///
/// **Порядок ключей сохраняется**: `jsonDecode` складывает объект в `Map`, а он
/// хранит порядок вставки. Менять его нельзя — отформатированный файл кладут
/// обратно в систему контроля версий, и разница должна остаться читаемой.
///
/// Бросает [FormatException] с местом, если разобрать не вышло: место увидит
/// человек.
String formatJson(String text) {
  final value = jsonDecode(text);

  return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
}

/// Где сломалось — строкой и столбцом, считая с единицы.
///
/// `FormatException` несёт смещение в знаках; человеку оно не говорит ничего, а
/// «строка 4, столбец 12» ведёт прямо туда. Смещения нет — возвращаем null, и
/// тогда причину говорят без места.
({int line, int column})? jsonErrorPlace(FormatException error, String text) {
  final at = error.offset;
  if (at == null || at < 0) {
    return null;
  }

  final upto = at > text.length ? text.length : at;
  var line = 1;
  var column = 1;
  for (var i = 0; i < upto; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }

  return (line: line, column: column);
}
