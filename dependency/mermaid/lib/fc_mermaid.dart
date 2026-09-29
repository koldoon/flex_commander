/// Диаграммы mermaid: врезка ```` ```mermaid ```` в документе рисуется картинкой.
///
/// Модуль получает текст врезки и отдаёт виджет — про markdown, про клавишу,
/// которой открыли документ, и про место показа он не знает ничего. Это и есть
/// проверка точки расширения из Г19.
///
/// Спецификация — `docs/spec/mermaid.md`.
library;

export 'src/mermaid_block.dart';
export 'src/mermaid_error.dart';
export 'src/mermaid_kind.dart';
export 'src/mermaid_module.dart';
