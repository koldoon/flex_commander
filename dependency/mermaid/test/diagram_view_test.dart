import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Показ диаграммы: пропорции и цвета.
void main() {
  final colors = DefaultColors();

  Future<Size> pumpDiagram(WidgetTester tester, String body, {required double parent, required double given}) async {
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

    // Возвращаем отношение: пропорции картинки и нарисованного должны совпасть.
    return Size(painted.width / layout.size.width, painted.height / layout.size.height);
  }

  testWidgets('картинка не растягивается по ширине врезки', (tester) async {
    // Врезка в документе растянута на всю колонку, а диаграмма узкая: раньше
    // `BoxFit.fill` растягивал её вместе с буквами.
    final ratio = await pumpDiagram(tester, 'A->>B: раз\n', parent: 900, given: 900);

    expect((ratio.width - ratio.height).abs(), lessThan(0.01), reason: 'по ширине и высоте масштаб должен совпасть');
  });

  testWidgets('широкая диаграмма ужимается, но пропорции держит', (tester) async {
    final ratio = await pumpDiagram(
      tester,
      'Раз->>Два: очень длинная подпись сообщения, которая заведомо шире отведённого места\n',
      parent: 300,
      given: 300,
    );

    expect((ratio.width - ratio.height).abs(), lessThan(0.01));
    expect(ratio.width, lessThan(1), reason: 'не влезла — значит ужата');
  });

  test('стрелки красятся цветом текста, а не бледной рамкой', () {
    // `panelBorder` — «белый 15%»: на нём стрелки выходили бледнее подписей.
    final theme = FcTheme(colors: colors, metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts());

    expect(theme.colors.rowText, isNot(theme.colors.panelBorder), reason: 'иначе проверка ничего не значит');
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
