import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Строки врезки: пустое и комментарии выброшены, номера сохранены.
void main() {
  test('номер строки — настоящий, а не порядковый', () {
    final lines = lexMermaid('\n%% заметка\n\nsequenceDiagram\n  A->>B: раз\n');

    expect(lines.map((line) => line.number), [4, 5]);
    expect(lines.map((line) => line.text), ['sequenceDiagram', 'A->>B: раз']);
  });

  test('комментарий — только целой строкой', () {
    // Два процента законно стоят в подписи, и резать по ним нельзя.
    final lines = lexMermaid('sequenceDiagram\n  A->>B: рост 5%% за год\n');

    expect(lines.last.text, 'A->>B: рост 5%% за год');
  });

  test('подпись делится по `<br/>` во всех написаниях', () {
    expect(mermaidLabelLines('раз<br/>два<br>три<br />четыре'), ['раз', 'два', 'три', 'четыре']);
  });

  test('подпись без переносов — одна строка', () {
    expect(mermaidLabelLines('просто текст'), ['просто текст']);
  });
}
