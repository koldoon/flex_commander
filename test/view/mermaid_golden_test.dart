import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок нарисованной диаграммы: шапки участников, стрелки с наконечниками,
/// пунктир, рамки `alt` и `loop`, нумерация.
///
/// Снимок ловит то, чего не ловят координаты: настоящий шрифт, цвета темы,
/// наконечники и пунктир (`docs/spec/mermaid.md`, §12).
///
/// Рисуется **сама диаграмма**, а не приложение вокруг неё: показ документа в
/// собранном приложении на дереве в памяти до кадра не доходит — это отдельная
/// беда, и разбираться с ней надо отдельно, а отрисовке оболочка вокруг ничего
/// не добавляет.
///
/// Обновление — рабочим процессом **Goldens** на раннере, а не локально: у
/// macOS 26 и 27 отрисовка шрифтов расходится.
void main() {
  // Тот самый пример, ради которого этап затевался.
  const source = '''
sequenceDiagram
    autonumber
    participant Cli as Client
    participant API as Cloud API
    participant T as Терминал
    participant CSO as CSO

    Cli->>API: POST /orders
    API-->>Cli: 200 { order_id }

    alt номер передан
        API->>CSO: выгрузка
    else номера нет
        API->>T: запрос номера
        T-->>API: { order_number }
        API->>API: счётчик 100…999
    end

    loop опрос
        Cli->>API: GET /orders/{id}
        API-->>Cli: заказ
    end
''';

  testWidgets('диаграмма последовательности совпадает с эталоном', (tester) async {
    final diagram = parseSequenceDiagram(source);
    final colors = DefaultColors();

    tester.view.physicalSize = const Size(900, 700);
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
              width: 880,
              child: MermaidDiagramView(maxWidth: 880, build: (measure) => layoutSequence(diagram, measure)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(find.byType(MermaidDiagramView), matchesGoldenFile('goldens/mermaid_sequence.png'));
  });
}
