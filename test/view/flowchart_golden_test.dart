import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок нарисованного графа: формы узлов, рамка подграфа, подписи рёбер,
/// пунктир и толстая линия, снятый цикл.
///
/// Снимок ловит то, чего не ловят координаты: очертания фигур, наконечники,
/// пунктир (`docs/spec/mermaid.md`, §7).
///
/// Рисуется **сам граф**, а не приложение вокруг него: показ документа в
/// собранном приложении на дереве в памяти до кадра не доходит — это отдельная
/// беда, записанная в §11.
///
/// Обновление — рабочим процессом **Goldens** на раннере, а не локально: у
/// macOS 26 и 27 отрисовка шрифтов расходится.
void main() {
  const source = '''
flowchart TD
    Start([Заказ создан]) --> Check{Номер передан?}
    Check -- да --> Upload[(Выгрузка в CSO)]
    Check -- нет --> Term[/Запрос терминала/]
    Term -.-> Check
    subgraph Опрос [Опрос статуса]
        Poll[[GET /orders]] --> Done((Готово))
    end
    Upload ==> Poll
    Done --> Start
''';

  testWidgets('граф совпадает с эталоном', (tester) async {
    final diagram = parseFlowchart(source);
    final colors = DefaultColors();

    tester.view.physicalSize = const Size(520, 560);
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
              width: 500,
              child: MermaidDiagramView(maxWidth: 500, build: (measure) => layoutFlowchart(diagram, measure)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(find.byType(MermaidDiagramView), matchesGoldenFile('goldens/flowchart.png'));
  });
}
