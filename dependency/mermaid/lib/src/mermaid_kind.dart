/// Вид диаграммы — по первому слову врезки.
///
/// Так же решает и сам mermaid: тип объявлен первой значащей строкой, и всё
/// остальное разбирается уже по его правилам.
enum MermaidKind {
  /// Последовательность сообщений между участниками.
  sequence('sequenceDiagram'),

  /// Граф из узлов и рёбер. `graph` — прежнее имя того же.
  flowchart('flowchart'),

  classDiagram('classDiagram'),
  stateDiagram('stateDiagram'),
  erDiagram('erDiagram'),
  journey('journey'),
  gantt('gantt'),
  pie('pie'),
  mindmap('mindmap'),
  timeline('timeline'),
  gitGraph('gitGraph'),

  /// Первое слово не опознано вовсе.
  unknown('');

  const MermaidKind(this.keyword);

  /// Слово, которым вид объявляют.
  final String keyword;
}

/// Опознать вид по тексту врезки.
///
/// Пустые строки, комментарии `%%` и настройки `%%{init}%%` пропускаются: они
/// законно стоят перед объявлением вида.
MermaidKind mermaidKindOf(String source) {
  for (final line in source.split('\n')) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('%%')) {
      continue;
    }

    return _byWord(_firstWord(text));
  }

  return MermaidKind.unknown;
}

/// Слово, которым врезка объявила свой вид; пусто — объявления нет вовсе.
///
/// Нужно для отказа: человеку говорят, **что именно** не опознано, а не
/// «что-то не то».
String mermaidFirstWordOf(String source) {
  for (final line in source.split('\n')) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('%%')) {
      continue;
    }

    return _firstWord(text);
  }

  return '';
}

/// Первое слово объявления: `flowchart TD` → `flowchart`.
///
/// Разделителем считается и пробел, и знаки, которыми пишут разновидности:
/// `stateDiagram-v2`, `sankey-beta`.
String _firstWord(String line) {
  final cut = line.indexOf(RegExp(r'[\s\-]'));

  return cut < 0 ? line : line.substring(0, cut);
}

MermaidKind _byWord(String word) {
  final name = word.toLowerCase();
  if (name == 'graph') {
    // Прежнее имя `flowchart`: документы с ним ещё пишут.
    return MermaidKind.flowchart;
  }

  for (final kind in MermaidKind.values) {
    if (kind != MermaidKind.unknown && kind.keyword.toLowerCase() == name) {
      return kind;
    }
  }

  return MermaidKind.unknown;
}
