import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Показ диаграммы: пропорции и цвета.
void main() {
  final colors = DefaultColors();

  Future<({Rect painted, Size wanted})> pumpDiagram(
    WidgetTester tester,
    String body, {
    required double parent,
    required double given,
  }) async {
    final diagram = parseSequenceDiagram('sequenceDiagram\n$body');
    late DiagramLayout layout;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: colors, metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: SizedBox(
            width: parent,
            height: 600,
            child: MermaidDiagramView(maxWidth: given, build: (measure) => layout = layoutSequence(diagram, measure)),
          ),
        ),
      ),
    );
    await tester.pump();

    // Именно `getRect`, а не `getSize`: размер отдаёт коробку **до**
    // преобразования, и масштаб в нём не виден вовсе — проверка проходила бы
    // впустую. Прямоугольник на экране преобразование учитывает.
    final painted = tester.getRect(
      find.descendant(of: find.byType(MermaidDiagramView), matching: find.byType(CustomPaint)).first,
    );

    return (painted: painted, wanted: layout.size);
  }

  /// Во сколько раз нарисованное отличается от посчитанного — по каждой стороне.
  Size ratioOf(({Rect painted, Size wanted}) shown) =>
      Size(shown.painted.width / shown.wanted.width, shown.painted.height / shown.wanted.height);

  testWidgets('картинка не растягивается по ширине врезки', (tester) async {
    // Врезка в документе растянута на всю колонку, а диаграмма узкая: раньше
    // `BoxFit.fill` растягивал её вместе с буквами.
    final ratio = ratioOf(await pumpDiagram(tester, 'A->>B: раз\n', parent: 900, given: 900));

    expect((ratio.width - ratio.height).abs(), lessThan(0.01), reason: 'по ширине и высоте масштаб должен совпасть');
  });

  testWidgets('узкая диаграмма стоит посередине отведённой ширины', (tester) async {
    final shown = await pumpDiagram(tester, 'A->>B: раз\n', parent: 900, given: 900);
    final field = tester.getRect(find.byType(MermaidDiagramView));

    expect(shown.painted.width, lessThan(field.width), reason: 'иначе центровку не на чем увидеть');
    expect(shown.painted.center.dx, moreOrLessEquals(field.center.dx, epsilon: 0.5));
  });

  testWidgets('широкая диаграмма ужимается, но пропорции держит', (tester) async {
    final ratio = ratioOf(
      await pumpDiagram(
        tester,
        'Раз->>Два: очень длинная подпись сообщения, которая заведомо шире отведённого места\n',
        parent: 300,
        given: 300,
      ),
    );

    expect((ratio.width - ratio.height).abs(), lessThan(0.01));
    expect(ratio.width, lessThan(1), reason: 'не влезла — значит ужата');
  });

  test('стрелки красятся цветом текста, а не бледной рамкой', () {
    // `panelBorder` — «белый 15%»: на нём стрелки выходили бледнее подписей.
    final theme = FcTheme(colors: colors, metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts());

    expect(theme.colors.rowText, isNot(theme.colors.panelBorder), reason: 'иначе проверка ничего не значит');
  });

  testWidgets('плашка участника инвертирована', (tester) async {
    late DiagramStyle style;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: colors, metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              style = DiagramStyle.of(context);

              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    // Плашка — цветом линий жизни, надпись на ней — цветом фона панели.
    expect(style.colorOf(DiagramInk.plate), style.colorOf(DiagramInk.faint));
    expect(style.text[DiagramTextRole.participant]?.color, colors.panelBackground);
  });

  testWidgets('линия вызова толще прочих', (tester) async {
    late DiagramStyle style;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: colors, metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              style = DiagramStyle.of(context);

              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(style.arrowStroke, style.stroke * 1.2);
  });

  testWidgets('стрелка ярче линии жизни', (tester) async {
    late DiagramStyle style;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: colors, metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              style = DiagramStyle.of(context);

              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(style.colorOf(DiagramInk.line), colors.rowText);
    expect(style.colorOf(DiagramInk.faint), colors.secondaryText);
    expect(style.colorOf(DiagramInk.line), isNot(colors.panelBorder));
  });
}
