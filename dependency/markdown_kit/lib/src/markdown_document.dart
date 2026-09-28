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

  /// Видимый текст документа — то, что человек читает, строками.
  ///
  /// По нему и ищут: искать по разметке значило бы находить звёздочки и
  /// решётки, которых на экране нет (`docs/spec/markdown-viewer.md`, §7).
  late final String plainText = _projected.$1.join('\n');

  /// Строка [plainText] → номер блока в [nodes].
  ///
  /// Так найденное превращается в место на экране: поиск говорит строку,
  /// а показу нужен блок, который надо показать.
  late final List<int> blockOfLine = _projected.$2;

  /// Обход делается один раз: строки и их блоки считаются вместе.
  late final (List<String>, List<int>) _projected = _projection();

  (List<String>, List<int>) _projection() {
    final lines = <String>[];
    final blocks = <int>[];

    for (var index = 0; index < nodes.length; index++) {
      for (final line in _linesOf(nodes[index])) {
        lines.add(line);
        blocks.add(index);
      }
    }

    return (lines, blocks);
  }

  /// Во что превращается узел на экране — построчно.
  ///
  /// Пустых строк не даём: поиск по ним не ходит, а номера строк они бы
  /// сдвинули.
  static List<String> _linesOf(md.Node node) {
    if (node is! md.Element) {
      final text = node.textContent.trim();

      return text.isEmpty ? const [] : [text];
    }

    switch (node.tag) {
      // Врезка кода — своими строками: в ней ищут так же, как в файле.
      case 'pre':
        return node.textContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

      // Ячейки строки таблицы — через табуляцию: на экране они стоят в ряд.
      case 'tr':
        final cells = node.children?.whereType<md.Element>().map((cell) => cell.textContent.trim()) ?? const [];
        final row = cells.where((cell) => cell.isNotEmpty).join('\t');

        return row.isEmpty ? const [] : [row];

      // Обёртки: своей строки не дают, но их содержимое — даёт.
      case 'ul':
      case 'ol':
      case 'blockquote':
      case 'table':
      case 'thead':
      case 'tbody':
      case 'section':
        return [for (final child in node.children ?? const <md.Node>[]) ..._linesOf(child)];

      // Разделитель читать нечего.
      case 'hr':
        return const [];

      default:
        final text = node.textContent.trim();

        return text.isEmpty ? const [] : [text];
    }
  }
}
