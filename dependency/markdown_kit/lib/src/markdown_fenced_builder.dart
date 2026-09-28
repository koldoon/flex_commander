import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_code_block.dart';

/// Кто рисует огороженные врезки ```` ```<язык> ````.
///
/// Библиотека сама умеет только показать их текстом. Здесь врезка либо уходит
/// объявленному рисовальщику (диаграмма), либо рисуется врезкой кода с
/// подсветкой — и в обоих случаях это делаем мы, а не она
/// (`docs/spec/markdown-viewer.md`, §4).
class FcFencedBlockBuilder extends MarkdownElementBuilder {
  FcFencedBlockBuilder({required this.blocks, required this.maxWidth});

  /// Объявленные рисовальщики, уже по убыванию приоритета.
  final List<MarkdownBlockSpec> blocks;

  /// Сколько места по ширине даём содержимому врезки.
  final double maxWidth;

  /// `pre` и так блочный тег, но сказать это надо: иначе библиотека не считает
  /// наш builder блочным и обходит врезку по строчному пути.
  @override
  bool isBlockElement() => true;

  /// Текст врезки собираем сами.
  ///
  /// Вернуть здесь что-то значило бы отдать его штатной ветке, которая завернёт
  /// текст в свою горизонтальную прокрутку с чужими отступами.
  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => null;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.whereType<md.Element>().where((child) => child.tag == 'code').firstOrNull;

    final classes = code?.attributes['class'] ?? '';
    final language = classes.startsWith(_languagePrefix) ? classes.substring(_languagePrefix.length).toLowerCase() : '';

    // Разбор добавляет в конец перевод строки, которого в тексте не было.
    final text = code?.textContent ?? element.textContent;
    final source = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;

    return _draw(
      context,
      MarkdownBlockRequest(
        language: language,
        source: source,
        metadata: element.attributes['data-metadata'] ?? '',
        maxWidth: maxWidth,
      ),
    );
  }

  /// Спросить рисовальщиков по очереди и нарисовать то, что вышло.
  ///
  /// Дисциплина та же, что у просмотрщиков: `Declined` — не мой язык,
  /// спрашиваем следующего; `Refused` — взялся и не смог, и тогда человек
  /// видит исходный текст **и причину**, а не пустое место.
  Widget _draw(BuildContext context, MarkdownBlockRequest request) {
    for (final spec in blocks) {
      if (!spec.accepts(request.language)) {
        continue;
      }
      try {
        return spec.build(context, request);
      } on MarkdownBlockDeclined {
        continue;
      } on MarkdownBlockRefused catch (refusal) {
        return FcCodeBlock(source: request.source, language: request.language, note: refusal.reason);
      } on Object {
        // Чужая ошибка в чужом модуле не должна уносить весь документ: врезка
        // становится текстом, остальное читается дальше.
        return FcCodeBlock(
          source: request.source,
          language: request.language,
          note: context.strings.tr('This block could not be drawn'),
        );
      }
    }

    return FcCodeBlock(source: request.source, language: request.language);
  }

  static const String _languagePrefix = 'language-';
}
