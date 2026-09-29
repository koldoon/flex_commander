import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Непонятое показывается, а не замалчивается.
///
/// Проверяется на **настоящем документе**: врезку рисует тот же показ, что и в
/// приложении, и отказ виден так же, как увидит человек.
void main() {
  final spec = MarkdownBlockSpec(
    id: 'mermaid',
    title: 'Mermaid diagrams',
    accepts: (language) => language == 'mermaid',
    build: buildMermaidBlock,
  );

  Future<void> pump(WidgetTester tester, String diagram) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FcMarkdownView(document: FcMarkdownDocument.parse('```mermaid\n$diagram\n```\n'), blocks: [spec]),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('незнакомый вид назван по имени', (tester) async {
    await pump(tester, 'quadrantChart\n  title Охват');

    expect(find.text('Unknown diagram type: quadrantChart'), findsOneWidget);
    expect(find.textContaining('quadrantChart'), findsWidgets, reason: 'исходник врезки остаётся на экране');
  });

  testWidgets('вид знаем, но ещё не рисуем — так и сказано', (tester) async {
    await pump(tester, 'sequenceDiagram\n  A->>B: привет');

    expect(find.text('sequenceDiagram is not drawn yet'), findsOneWidget);
  });

  testWidgets('и для графа тоже', (tester) async {
    await pump(tester, 'flowchart TD\n  A-->B');

    expect(find.text('flowchart is not drawn yet'), findsOneWidget);
  });

  testWidgets('врезка без объявления вида', (tester) async {
    await pump(tester, '%% тут только комментарий');

    expect(find.text('The block does not say what kind of diagram it is'), findsOneWidget);
  });

  testWidgets('исходник врезки виден целиком: его и будут чинить', (tester) async {
    await pump(tester, 'sequenceDiagram\n  Cli->>API: POST /orders');

    expect(find.textContaining('Cli->>API: POST /orders'), findsOneWidget);
  });

  testWidgets('ошибка разбора названа с номером строки', (tester) async {
    // Считается по **исходной** врезке: пустые строки и комментарии до неё
    // номер не сдвигают.
    await pump(tester, 'sequenceDiagram\n  A->>B: раз\n  end');

    expect(find.text('Line 3: this end closes nothing'), findsOneWidget);
  });

  testWidgets('незакрытая рамка указывает на своё начало, а не на конец', (tester) async {
    await pump(tester, 'sequenceDiagram\n  alt да\n    A->>B: раз');

    expect(find.text('Line 2: this block is never closed'), findsOneWidget);
  });

  testWidgets('верная диаграмма разбирается и говорит, что пока не рисуется', (tester) async {
    await pump(tester, 'sequenceDiagram\n  autonumber\n  A->>B: раз\n  alt да\n    B-->>A: два\n  end');

    expect(find.text('sequenceDiagram is not drawn yet'), findsOneWidget);
  });

  testWidgets('чужой язык врезки этот рисовальщик не трогает', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FcMarkdownView(document: FcMarkdownDocument.parse('```dart\nvoid main() {}\n```\n'), blocks: [spec]),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('is not drawn yet'), findsNothing);
    expect(find.byType(FcCodeBlock), findsOneWidget);
  });
}
