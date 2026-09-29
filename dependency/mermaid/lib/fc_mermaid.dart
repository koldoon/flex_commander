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
export 'src/draw/diagram_layout.dart';
export 'src/draw/diagram_theme.dart';
export 'src/draw/diagram_view.dart';
export 'src/draw/diagram_text.dart';
export 'src/flowchart/flowchart_geometry.dart';
export 'src/flowchart/flowchart_layering.dart';
export 'src/flowchart/flowchart_model.dart';
export 'src/flowchart/flowchart_parser.dart';
export 'src/sequence/sequence_layout.dart';
export 'src/sequence/sequence_model.dart';
export 'src/sequence/sequence_parser.dart';
export 'src/text/lexer.dart';
