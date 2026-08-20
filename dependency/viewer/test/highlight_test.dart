import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подсветка отдаёт по спану на строку — показ рисует по строке за раз.
void main() {
  const base = TextStyle(fontSize: 12);
  const colors = DefaultColors();
  late ReHighlighter highlighter;

  setUp(() => highlighter = ReHighlighter(colors));

  /// Весь текст спана — чтобы сверять содержимое, не разбирая дерево.
  String textOf(TextSpan span) {
    final buffer = StringBuffer(span.text ?? '');
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) {
        buffer.write(textOf(child));
      }
    }
    return buffer.toString();
  }

  /// Цвета, встреченные в строке.
  Set<Color?> colorsOf(TextSpan span) {
    final found = <Color?>{span.style?.color};
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) {
        found.addAll(colorsOf(child));
      }
    }
    return found;
  }

  group('язык по имени файла', () {
    test('по расширению', () {
      expect(ReHighlighter.languageOf('main.dart'), 'dart');
      expect(ReHighlighter.languageOf('app.py'), 'python');
      expect(ReHighlighter.languageOf('settings.yml'), 'yaml');
      expect(ReHighlighter.languageOf('index.html'), 'xml');
    });

    test('по имени, когда расширения нет вовсе', () {
      expect(ReHighlighter.languageOf('Makefile'), 'makefile');
      expect(ReHighlighter.languageOf('Dockerfile'), 'dockerfile');
    });

    test('незнакомое расширение — ничем', () {
      expect(ReHighlighter.languageOf('notes.qwerty'), isNull);
      expect(ReHighlighter.languageOf('notes'), isNull);
      expect(ReHighlighter.languageOf('archive.'), isNull);
    });
  });

  group('строки', () {
    test('спанов ровно столько же, сколько строк', () {
      final lines = ['void main() {', '  print("привет");', '}'];

      final spans = highlighter.highlight(lines, fileName: 'main.dart', base: base);

      expect(spans, hasLength(lines.length));
      for (var i = 0; i < lines.length; i++) {
        expect(textOf(spans[i]), lines[i], reason: 'строка $i');
      }
    });

    test('многострочный комментарий не рассыпается', () {
      // Начало в одной строке, конец в другой: построчный разбор их не связал
      // бы, и вторая строка осталась бы обычным кодом.
      final lines = ['/* начало', '   продолжение', '   конец */', 'var x = 1;'];

      final spans = highlighter.highlight(lines, fileName: 'main.dart', base: base);

      expect(spans, hasLength(4));
      final comment = colors.syntaxComment;
      expect(colorsOf(spans[1]), contains(comment));
      expect(colorsOf(spans[2]), contains(comment));
      // А код после комментария — уже не комментарий.
      expect(colorsOf(spans[3]), isNot(contains(comment)));
    });

    test('пустые строки остаются на своих местах', () {
      final lines = ['var a = 1;', '', 'var b = 2;'];

      final spans = highlighter.highlight(lines, fileName: 'main.dart', base: base);

      expect(spans, hasLength(3));
      expect(textOf(spans[1]), isEmpty);
    });

    test('цвета берутся у оформления, а не у библиотеки', () {
      final spans = highlighter.highlight(['var x = 1;'], fileName: 'main.dart', base: base);

      expect(colorsOf(spans.single), contains(colors.syntaxKeyword));
    });

    test('незнакомый язык — простой текст без цвета', () {
      final lines = ['что-то', 'ещё'];

      final spans = highlighter.highlight(lines, fileName: 'notes.qwerty', base: base);

      expect(spans, hasLength(2));
      expect(textOf(spans.first), 'что-то');
      expect(colorsOf(spans.first), {base.color});
    });
  });

  group('без подсветки', () {
    test('строка приходит как есть', () {
      const plain = PlainHighlighter();

      final spans = plain.highlight(['раз', 'два'], fileName: 'notes.txt', base: base);

      expect(spans.map(textOf), ['раз', 'два']);
    });
  });
}
