import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок нарисованной ER-диаграммы: таблицы сущностей с колонками атрибутов,
/// все четыре знака кардинальности, пунктир неидентифицирующей связи, подписи
/// (`docs/spec/mermaid.md`, §7а).
///
/// Рисуется **сама диаграмма**, а не приложение вокруг неё — по той же причине,
/// что и у графа (§11). Обновление — рабочим процессом **Goldens** на раннере, а
/// не локально: у macOS 26 и 27 отрисовка шрифтов расходится.
void main() {
  const source = '''
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE-ITEM : contains
    CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
    ORDER |o--o| INVOICE : "billed by"
    CUSTOMER {
        string name
        string custNumber PK "the number"
    }
    ORDER {
        int orderNumber PK
        string deliveryAddress FK
    }
''';

  testWidgets('ER-диаграмма совпадает с эталоном', (tester) async {
    final diagram = parseErDiagram(source);
    final colors = DefaultColors();

    tester.view.physicalSize = const Size(620, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          extensions: [
            FcTheme(colors: colors, metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          backgroundColor: colors.panelBackground,
          body: Center(
            child: SizedBox(
              width: 600,
              child: MermaidDiagramView(maxWidth: 600, build: (measure) => layoutErDiagram(diagram, measure)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(find.byType(MermaidDiagramView), matchesGoldenFile('goldens/er_diagram.png'));
  });
}
