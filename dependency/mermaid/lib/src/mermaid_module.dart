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

  // Что именно не так — подставляется в «Строка N: …».
  'the diagram is empty': 'диаграмма пуста',
  'this block is never closed': 'эта рамка не закрыта',
  'this end closes nothing': 'этот end ничего не закрывает',
  'this line divides a block, but no block is open': 'эта строка делит рамку, но ни одна рамка не открыта',
  'this line does not say who the participant is': 'не сказано, кто участник',
  'this line does not say whose activation it is': 'не сказано, чью активность открывают',
  'a note needs a colon and its text': 'у заметки нет двоеточия и текста',
  'a note must say left of, right of or over': 'у заметки должно быть left of, right of или over',
  'a message needs both sides of the arrow': 'у сообщения должны быть обе стороны стрелки',
  'this is not a direction': 'это не направление',
  'this line does not say what the subgraph is': 'не сказано, что за подграф',
  'this line does not say what the node is': 'не сказано, что за узел',
  'a link needs both of its ends': 'у связи должны быть оба конца',
  'a direction inside a subgraph is not drawn yet': 'направление внутри подграфа пока не рисуется',
  'invisible links are not drawn yet': 'невидимые связи пока не рисуются',
  'a link with heads at both ends is not drawn yet': 'связь с наконечниками на обоих концах пока не рисуется',
  'do not understand this line': 'непонятная строка',
};
