import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вид диаграммы опознаётся по первому значащему слову.
void main() {
  test('последовательность', () {
    expect(mermaidKindOf('sequenceDiagram\n  A->>B: привет\n'), MermaidKind.sequence);
  });

  test('граф — и по новому имени, и по старому', () {
    expect(mermaidKindOf('flowchart TD\n  A-->B\n'), MermaidKind.flowchart);
    expect(mermaidKindOf('graph LR\n  A-->B\n'), MermaidKind.flowchart);
  });

  test('разновидность через дефис — тот же вид', () {
    expect(mermaidKindOf('stateDiagram-v2\n  [*] --> s1\n'), MermaidKind.stateDiagram);
  });

  test('пустые строки и комментарии перед объявлением не мешают', () {
    expect(mermaidKindOf('\n%% это комментарий\n\nsequenceDiagram\n'), MermaidKind.sequence);
  });

  test('настройка `%%{init}%%` тоже пропускается', () {
    expect(mermaidKindOf("%%{init: {'theme':'dark'}}%%\nflowchart TD\n"), MermaidKind.flowchart);
  });

  test('регистр слова не важен', () {
    expect(mermaidKindOf('SEQUENCEDIAGRAM\n'), MermaidKind.sequence);
  });

  test('незнакомое слово — unknown, и оно запоминается для отказа', () {
    expect(mermaidKindOf('quadrantChart\n  title Охват\n'), MermaidKind.unknown);
    expect(mermaidFirstWordOf('quadrantChart\n  title Охват\n'), 'quadrantChart');
  });

  test('пустая врезка объявления не несёт', () {
    expect(mermaidKindOf('\n\n%% и всё\n'), MermaidKind.unknown);
    expect(mermaidFirstWordOf('\n\n%% и всё\n'), isEmpty);
  });

  test('у каждого вида своё слово, и они не повторяются', () {
    final words = [
      for (final kind in MermaidKind.values)
        if (kind != MermaidKind.unknown) kind.keyword,
    ];

    expect(words.toSet(), hasLength(words.length));
    expect(words, isNot(contains('')));
  });
}
