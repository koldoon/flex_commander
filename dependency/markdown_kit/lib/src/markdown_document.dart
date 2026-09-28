import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

/// Разобранный документ: узлы верхнего уровня — по одному на блок.
///
/// Разбор отделён от показа затем, чтобы документ строился **лениво**:
/// библиотека складывает все виджеты разом и отдаёт их в `ListView(children:)`
/// (`docs/spec/markdown-viewer.md`, §5), а на файле в треть мегабайта — а
/// `docs/roadmap.md` этого проекта именно таков — это тысячи виджетов до
/// первого кадра.
class FcMarkdownDocument {
  FcMarkdownDocument._(this.source, this.nodes);

  /// Разобрать текст документа.
  factory FcMarkdownDocument.parse(String source) {
    final document = md.Document(extensionSet: extensions, encodeHtml: false);
    final lines = const LineSplitter().convert(source);

    return FcMarkdownDocument._(source, document.parseLines(lines));
  }

  /// Набор синтаксиса — свой, а не готовый.
  ///
  /// Взят `gitHubWeb` без **одного** правила: `AlertBlockSyntax` делает из
  /// `> [!NOTE]` узел `div`, а показ такого тега не знает — `div` нет среди его
  /// блочных, и разбор падает с «Too many elements» прямо в отрисовке. Это не
  /// наша оплошность и не чинится настройкой: библиотека умеет ровно свои теги
  /// (`markdown-viewer.md`, §10).
  ///
  /// Всё остальное из `gitHubWeb` на месте: таблицы, списки задач, сноски
  /// (они есть уже в `gitHubFlavored`), якоря заголовков и эмодзи.
  ///
  /// Один и тот же набор идёт и в разбор, и в показ — иначе узлы разъедутся.
  static final md.ExtensionSet extensions = md.ExtensionSet(
    List<md.BlockSyntax>.unmodifiable(<md.BlockSyntax>[
      const md.FencedCodeBlockSyntax(),
      const md.HeaderWithIdSyntax(),
      const md.SetextHeaderWithIdSyntax(),
      const md.TableSyntax(),
      const md.UnorderedListWithCheckboxSyntax(),
      const md.OrderedListWithCheckboxSyntax(),
      const md.FootnoteDefSyntax(),
    ]),
    List<md.InlineSyntax>.unmodifiable(<md.InlineSyntax>[
      md.InlineHtmlSyntax(),
      md.StrikethroughSyntax(),
      md.EmojiSyntax(),
      md.AutolinkExtensionSyntax(),
    ]),
  );

  /// Исходный текст — его показывает Raw и по нему ищут в нём.
  final String source;

  /// Узлы верхнего уровня: по одному на блок документа.
  final List<md.Node> nodes;

  /// Сколько блоков в документе.
  int get length => nodes.length;
}
