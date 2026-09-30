/// Где в тексте сломался разбор — строкой и столбцом, считая с единицы.
///
/// [FormatException] несёт смещение в знаках; человеку оно не говорит ничего, а
/// «строка 4, столбец 12» ведёт прямо туда. Смещения нет — возвращаем null, и
/// тогда причину говорят без места (`docs/spec/formatters.md`, §6).
///
/// Живёт здесь, а не у форматтера json: смещение переводят в место оба экрана —
/// показ и редактор, — а json-у это не нужно вовсе. Считает это про **текст**, а
/// не про json, и имя у него про текст.
({int line, int column})? placeOfError(FormatException error, String text) {
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
