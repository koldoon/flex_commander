/// Строка врезки — с её номером.
///
/// Номер нужен ради отказа: человеку говорят, **где** сломалось
/// (`docs/spec/mermaid.md`, §10), и считать его задним числом уже не по чему —
/// пустые строки и комментарии к этому моменту выброшены.
class MermaidLine {
  const MermaidLine(this.number, this.text);

  /// Номер во врезке, считая с единицы.
  final int number;

  /// Текст без отступа и без комментария.
  final String text;

  @override
  String toString() => '$number: $text';
}

/// Разложить врезку на значащие строки.
///
/// Выбрасывается пустое и комментарии. Комментарий — это строка, **начинающаяся**
/// с `%%`: так его и описывает mermaid, а резать по `%%` в середине опасно —
/// два процента законно встречаются в подписи («рост 5%%»).
List<MermaidLine> lexMermaid(String source) {
  final lines = <MermaidLine>[];
  final raw = source.split('\n');

  for (var i = 0; i < raw.length; i++) {
    final text = raw[i].trim();
    if (text.isEmpty || text.startsWith('%%')) {
      continue;
    }
    lines.add(MermaidLine(i + 1, text));
  }

  return lines;
}

/// Разбить подпись на строки по `<br/>`.
///
/// Пишут его по-разному — `<br>`, `<br/>`, `<br />`, — и все три означают одно.
List<String> mermaidLabelLines(String label) {
  final parts = label.split(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false));

  return [for (final part in parts) part.trim()];
}
