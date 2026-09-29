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
    await pump(tester, 'classDiagram\n  class Кошка');

    expect(find.text('classDiagram is not drawn yet'), findsOneWidget);
  });

  testWidgets('верный граф рисуется картинкой, а не текстом', (tester) async {
    await pump(tester, 'flowchart TD\n  A[Начало] --> B{Развилка}');

    expect(find.byType(MermaidDiagramView), findsOneWidget);
    expect(find.text('flowchart is not drawn yet'), findsNothing);
    expect(find.textContaining('flowchart TD'), findsNothing, reason: 'исходника на экране быть не должно');
  });

  testWidgets('кривой граф называет строку, а не «пока не рисуется»', (tester) async {
    // Разбор подключён раньше отрисовки нарочно: опечатку человеку стоит
    // показать сегодня, а не ждать картинки (`docs/spec/mermaid.md`, §7).
    await pump(tester, 'flowchart TD\n  A --> B\n  end');

    expect(find.text('Line 3: this end closes nothing'), findsOneWidget);
    expect(find.text('flowchart is not drawn yet'), findsNothing);
  });

  testWidgets('незакрытый подграф указывает на своё начало', (tester) async {
    await pump(tester, 'flowchart TD\n  subgraph S\n    A --> B');

    expect(find.text('Line 2: this block is never closed'), findsOneWidget);
  });

  testWidgets('врезка без объявления вида', (tester) async {
    await pump(tester, '%% тут только комментарий');

    expect(find.text('The block does not say what kind of diagram it is'), findsOneWidget);
  });

  testWidgets('исходник врезки виден целиком: его и будут чинить', (tester) async {
    // На том виде, который ещё не рисуется: у нарисованного исходника на
    // экране нет — есть картинка.
    await pump(tester, 'gantt\n  title План');

    expect(find.textContaining('title План'), findsOneWidget);
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

  testWidgets('верная последовательность рисуется картинкой, а не текстом', (tester) async {
    await pump(tester, 'sequenceDiagram\n  autonumber\n  A->>B: раз\n  alt да\n    B-->>A: два\n  end');

    expect(find.byType(MermaidDiagramView), findsOneWidget);
    expect(find.byType(FcCodeBlock), findsNothing, reason: 'нарисованному исходник не нужен');
    expect(find.textContaining('is not drawn yet'), findsNothing);
  });

  testWidgets('нарисованная диаграмма умещается в данную ширину', (tester) async {
    await pump(tester, 'sequenceDiagram\n  Очень->>Длинный: подпись, которая заведомо шире врезки в шестьсот точек');

    final box = tester.getRect(find.byType(MermaidDiagramView));
    expect(box.width, lessThanOrEqualTo(600));
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
