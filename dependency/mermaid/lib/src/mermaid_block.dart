import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'mermaid_error.dart';
import 'mermaid_kind.dart';
import 'sequence/sequence_parser.dart';

/// Нарисовать врезку ```` ```mermaid ````.
///
/// Разбирается вид, и дальше — три исхода, и все три человек видит словами
/// (`docs/spec/mermaid.md`, §10):
///
/// * вид не опознан — говорим, какое слово не поняли;
/// * вид знаем, но ещё не рисуем — говорим и это, а не рисуем пустоту;
/// * ошибка разбора — говорим **с номером строки**.
///
/// Показывает отказ не этот код, а показ markdown: он рисует исходный текст
/// врезки и причину над ним. Так объяснение стоит на месте картинки, а не
/// уезжает в тост, которого в документе никто не ждёт.
Widget buildMermaidBlock(BuildContext context, MarkdownBlockRequest request) {
  final said = context.strings;
  final kind = mermaidKindOf(request.source);

  if (kind == MermaidKind.unknown) {
    final word = mermaidFirstWordOf(request.source);

    throw MarkdownBlockRefused(
      word.isEmpty
          ? said.tr('The block does not say what kind of diagram it is')
          : said.tr('Unknown diagram type: {kind}', args: {'kind': word}),
    );
  }

  try {
    return _draw(context, kind, request);
  } on MermaidError catch (error) {
    throw MarkdownBlockRefused(
      said.tr('Line {line}: {what}', args: {'line': error.line, 'what': said.tr(error.message)}),
    );
  }
}

/// Собственно отрисовка.
///
/// Рисовать пока не умеет никто, но **разобрать** последовательность мы уже
/// умеем — и разбираем: опечатку в диаграмме человеку стоит показать сегодня, а
/// не ждать, пока появится картинка. Отказ «пока не рисуется» приходит после
/// разбора, а не вместо него.
Widget _draw(BuildContext context, MermaidKind kind, MarkdownBlockRequest request) {
  if (kind == MermaidKind.sequence) {
    // Разбор бросит `MermaidError` с номером строки — его поймает вызывающий.
    parseSequenceDiagram(request.source);
  }

  throw MarkdownBlockRefused(context.strings.tr('{kind} is not drawn yet', args: {'kind': kind.keyword}));
}
