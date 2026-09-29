/// Ошибка разбора — с номером строки.
///
/// Номер обязателен: диаграмма на сорок строк без него превращается в игру
/// «найди опечатку» (`docs/spec/mermaid.md`, §10).
class MermaidError implements Exception {
  const MermaidError(this.line, this.message);

  /// Номер строки во врезке, считая с единицы.
  final int line;

  /// Что именно не так — по-английски: это ключ перевода.
  final String message;

  @override
  String toString() => 'Line $line: $message';
}
