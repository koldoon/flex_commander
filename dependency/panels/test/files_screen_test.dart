import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Панели как экран: модуль ставит его при запуске, ядро о панелях не знает.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
        ..home = '/home',
      modules: [const Panels()],
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: AppScope(
          controller: runtime.app,
          child: Scaffold(body: Builder(builder: (context) => runtime.app.screens.active!.build(context))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('модуль ставит экран при сборке приложения, до первого кадра', () async {
    // Стартовая команда модуля выполняется при установке — панели стоят на
    // экране ещё до того, как приложение начнёт читать каталоги.
    expect(runtime.app.screens.active?.id, Screens.files);
  });

  test('фокус экрану панелей не нужен: активную панель знает приложение', () async {
    await runtime.app.start();

    expect(runtime.app.screens.active?.takesFocus, isFalse);
  });

  test('таблица файлов объявлена штатным видом содержимого', () async {
    await runtime.app.start();

    // Ядро своих видов не знает вовсе — этот принесён модулем.
    expect(runtime.app.viewports.builderFor(PanelViewports.files), isNotNull);
  });

  testWidgets('экран собирает обе панели и разделитель между ними', (tester) async {
    await runtime.app.start();
    await pumpScreen(tester);

    expect(find.byType(SplitView), findsOneWidget);
    expect(find.byType(PanelView), findsNWidgets(2));
    // Содержимое панели рисуется тем же видом, что объявлен модулем: имя и
    // расширение стоят в своих колонках.
    expect(find.byType(FileTable), findsNWidgets(2));
    expect(find.text('notes'), findsWidgets);
  });

  testWidgets('панели прижаты к своим краям окна', (tester) async {
    await runtime.app.start();
    await pumpScreen(tester);

    final panels = tester.widgetList<PanelView>(find.byType(PanelView)).toList();

    expect(panels.first.outerEdge, PanelOuterEdge.left);
    expect(panels.last.outerEdge, PanelOuterEdge.right);
  });
}
