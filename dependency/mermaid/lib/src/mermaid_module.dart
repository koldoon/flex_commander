import 'package:fc_ui_api/fc_ui_api.dart';

import 'mermaid_block.dart';

/// Диаграммы mermaid — первый потребитель точки расширения из Г19.
///
/// Модуль объявляет **одну** вещь: чем рисовать врезку ```` ```mermaid ````.
/// Ни команд, ни клавиш, ни настроек у него нет. Выключите его — врезка снова
/// станет врезкой кода, и это единственное, что изменится
/// (`docs/spec/mermaid.md`, §3).
class Mermaid implements FcFrontendModule {
  const Mermaid();

  @override
  String get id => 'fc.mermaid';

  @override
  String get title => 'Mermaid diagrams';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    registry.markdownBlock(
      MarkdownBlockSpec(
        id: 'mermaid',
        title: 'Mermaid diagrams',
        accepts: (language) => language == 'mermaid',
        build: buildMermaidBlock,
      ),
    );
  }
}

/// Русские строки диаграмм.
const Map<String, String> _russian = {
  'Mermaid diagrams': 'Диаграммы mermaid',

  // Отказы. Каждый виден на месте самой врезки, вместо картинки.
  'The block does not say what kind of diagram it is': 'Во врезке не сказано, какая это диаграмма',
  'Unknown diagram type: {kind}': 'Неизвестный вид диаграммы: {kind}',
  '{kind} is not drawn yet': '{kind} пока не рисуется',
  'Line {line}: {what}': 'Строка {line}: {what}',
};
