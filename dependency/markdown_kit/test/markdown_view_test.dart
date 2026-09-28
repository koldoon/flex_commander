import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Рисовальщик врезки для теста: что объявил, то и делает.
MarkdownBlockSpec _spec(
  String id, {
  String language = 'mermaid',
  int priority = 0,
  Widget Function(BuildContext, MarkdownBlockRequest)? build,
}) => MarkdownBlockSpec(
  id: id,
  title: 'Block $id',
  priority: priority,
  accepts: (name) => name == language,
  build: build ?? (context, request) => Text('нарисовал $id: ${request.source}'),
);

/// Показ markdown: вёрстка, ленивость и дисциплина врезок.
void main() {
  Future<void> pump(
    WidgetTester tester,
    String source, {
    List<MarkdownBlockSpec> blocks = const [],
    void Function(String text, String? href, String title)? onTapLink,
    Size size = const Size(600, 400),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: FcMarkdownView(document: FcMarkdownDocument.parse(source), blocks: blocks, onTapLink: onTapLink),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('вёрстка', () {
    testWidgets('заголовок и абзац показаны текстом, а не разметкой', (tester) async {
      await pump(tester, '# Заголовок\n\nПросто абзац.\n');

      expect(find.text('Заголовок'), findsOneWidget);
      expect(find.text('Просто абзац.'), findsOneWidget);
      expect(find.textContaining('#'), findsNothing);
    });

    testWidgets('цитата, таблица и эмодзи показываются', (tester) async {
      await pump(tester, '> Осторожно.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nГотово :tada:\n');

      expect(find.textContaining('Осторожно.'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('🎉'), findsOneWidget);
    });

    testWidgets('врезка GitHub не роняет показ', (tester) async {
      // Она разбирается обычной цитатой: правило, делавшее из неё `div`, в
      // набор не входит — на нём отрисовка падала.
      await pump(tester, '> [!NOTE]\n> Осторожно.\n');

      expect(find.textContaining('Осторожно.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('врезки', () {
    testWidgets('никто не объявлен — врезка остаётся врезкой кода', (tester) async {
      await pump(tester, '```dart\nvoid main() {}\n```\n');

      expect(find.byType(FcCodeBlock), findsOneWidget);
      expect(find.textContaining('void main()'), findsOneWidget);
    });

    testWidgets('объявленный рисовальщик берётся за свой язык', (tester) async {
      await pump(tester, '```mermaid\nA-->B\n```\n', blocks: [_spec('mermaid')]);

      expect(find.text('нарисовал mermaid: A-->B'), findsOneWidget);
      expect(find.byType(FcCodeBlock), findsNothing);
    });

    testWidgets('чужой язык он не трогает', (tester) async {
      await pump(tester, '```dart\nvoid main() {}\n```\n', blocks: [_spec('mermaid')]);

      expect(find.byType(FcCodeBlock), findsOneWidget);
    });

    testWidgets('«не мой язык» — спрашивают следующего', (tester) async {
      await pump(
        tester,
        '```mermaid\nA-->B\n```\n',
        blocks: [
          _spec('first', priority: 10, build: (context, request) => throw const MarkdownBlockDeclined()),
          _spec('second'),
        ],
      );

      expect(find.text('нарисовал second: A-->B'), findsOneWidget);
    });

    testWidgets('«взялся и не смог» — виден исходник и причина', (tester) async {
      await pump(
        tester,
        '```mermaid\nA-->B\n```\n',
        blocks: [_spec('mermaid', build: (context, request) => throw const MarkdownBlockRefused('Строка 1: не понял'))],
      );

      expect(find.text('Строка 1: не понял'), findsOneWidget);
      expect(find.textContaining('A-->B'), findsOneWidget);
    });

    testWidgets('чужая ошибка не уносит документ', (tester) async {
      await pump(
        tester,
        '# Заголовок\n\n```mermaid\nA-->B\n```\n\nХвост.\n',
        blocks: [_spec('mermaid', build: (context, request) => throw StateError('сломался'))],
      );

      // Документ цел, врезка стала текстом с объяснением.
      expect(find.text('Заголовок'), findsOneWidget);
      expect(find.text('Хвост.'), findsOneWidget);
      expect(find.text('This block could not be drawn'), findsOneWidget);
      expect(find.textContaining('A-->B'), findsOneWidget);
    });

    testWidgets('ширина доезжает до рисовальщика', (tester) async {
      late double given;
      await pump(
        tester,
        '```mermaid\nA-->B\n```\n',
        blocks: [
          _spec(
            'mermaid',
            build: (context, request) {
              given = request.maxWidth;
              return const SizedBox.shrink();
            },
          ),
        ],
        size: const Size(480, 300),
      );

      expect(given, greaterThan(0), reason: 'диаграмме нужна ширина до раскладки');
      expect(given, lessThanOrEqualTo(480));
    });
  });

  group('ленивость', () {
    testWidgets('далёкий блок не строится, пока до него не долистали', (tester) async {
      final source = [for (var i = 0; i < 300; i++) 'Блок номер $i.'].join('\n\n');

      await pump(tester, source, size: const Size(400, 200));

      expect(find.text('Блок номер 0.'), findsOneWidget);
      expect(
        find.text('Блок номер 299.'),
        findsNothing,
        reason: 'весь документ разом — это тысячи виджетов до первого кадра',
      );
    });

    testWidgets('долистали — построился', (tester) async {
      final source = [for (var i = 0; i < 300; i++) 'Блок номер $i.'].join('\n\n');

      await pump(tester, source, size: const Size(400, 200));
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();

      expect(find.text('Блок номер 0.'), findsNothing);
      expect(find.textContaining('Блок номер'), findsWidgets);
    });
  });

  group('ссылки', () {
    testWidgets('нажатие уходит наружу', (tester) async {
      String? tapped;
      await pump(
        tester,
        'Читайте [документацию](https://example.org).\n',
        onTapLink: (text, href, title) {
          tapped = href;
        },
      );

      await tester.tap(find.textContaining('документацию'));
      await tester.pump();

      expect(tapped, 'https://example.org');
    });
  });
}
