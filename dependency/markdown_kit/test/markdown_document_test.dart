import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

/// Разбор документа: по узлу на блок — на этом стоит ленивый показ.
void main() {
  test('по узлу на блок верхнего уровня', () {
    final document = FcMarkdownDocument.parse('# Заголовок\n\nАбзац.\n\nВторой абзац.\n');

    expect(document.length, 3);
    expect((document.nodes.first as md.Element).tag, 'h1');
  });

  test('врезка кода — один блок, а не строки', () {
    final document = FcMarkdownDocument.parse('Текст\n\n```dart\nvoid main() {}\nprint(1);\n```\n');

    expect(document.length, 2);
    expect((document.nodes.last as md.Element).tag, 'pre');
  });

  test('пустой документ — ни одного блока, и это не падение', () {
    expect(FcMarkdownDocument.parse('').length, 0);
    expect(FcMarkdownDocument.parse('   \n\n  \n').length, 0);
  });

  test('исходник хранится как есть: по нему показывают Raw', () {
    const source = '# Заголовок\n\nАбзац.\n';

    expect(FcMarkdownDocument.parse(source).source, source);
  });

  group('набор синтаксиса', () {
    test('таблицы, сноски, списки задач и эмодзи на месте', () {
      final table = FcMarkdownDocument.parse('| a | b |\n|---|---|\n| 1 | 2 |\n');
      expect((table.nodes.single as md.Element).tag, 'table');

      final footnote = FcMarkdownDocument.parse('Текст[^1]\n\n[^1]: сноска\n');
      expect(footnote.nodes.map((node) => (node as md.Element).tag), ['p', 'section']);

      final tasks = FcMarkdownDocument.parse('- [x] сделано\n- [ ] нет\n');
      expect((tasks.nodes.single as md.Element).tag, 'ul');

      final emoji = FcMarkdownDocument.parse('Готово :tada:\n');
      expect(emoji.nodes.single.textContent, contains('🎉'));
    });

    test('заголовок получает якорь: по нему ходят ссылки внутри документа', () {
      final heading = FcMarkdownDocument.parse('# Как это устроено\n');

      expect((heading.nodes.single as md.Element).generatedId, isNotNull);
    });

    test('врезка GitHub остаётся цитатой, а не узлом, которого показ не знает', () {
      // `AlertBlockSyntax` делает `div`, на котором отрисовка падает; поэтому
      // его в наборе нет, и `> [!NOTE]` разбирается обычной цитатой
      // (`docs/spec/markdown-viewer.md`, §10).
      final alert = FcMarkdownDocument.parse('> [!NOTE]\n> Осторожно.\n');

      expect((alert.nodes.single as md.Element).tag, 'blockquote');
    });
  });

  test('язык врезки доезжает до показа классом', () {
    final document = FcMarkdownDocument.parse('```dart\nvoid main() {}\n```\n');

    final pre = document.nodes.single as md.Element;
    final code = pre.children!.whereType<md.Element>().single;

    expect(code.attributes['class'], 'language-dart');
  });

  test('хвост info-строки доезжает отдельно', () {
    final document = FcMarkdownDocument.parse('```mermaid theme=neutral\nA-->B\n```\n');

    final pre = document.nodes.single as md.Element;

    expect(pre.attributes['data-metadata'], 'theme=neutral');
  });
}
