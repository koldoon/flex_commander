import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_commander/view/split_view.dart';
import 'package:flex_commander/view/app_shell.dart';
import 'package:flex_commander/view/function_bar/function_bar.dart';

/// Размеры темы с полями по краям окна: остальное — как в теме по умолчанию.
class _MetricsWithSides extends DefaultMetrics {
  const _MetricsWithSides();

  @override
  double get windowSidePadding => 20;
}

/// И наоборот — без полей: содержимое прижато к краям окна.
class _MetricsFlush extends DefaultMetrics {
  const _MetricsFlush();

  @override
  double get windowSidePadding => 0;
}

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

  Future<void> pumpScreen(WidgetTester tester, {FcMetrics metrics = const DefaultMetrics()}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(
              colors: const DefaultColors(),
              metrics: metrics,
              icons: const DefaultIcons(),
              fonts: const DefaultFonts(),
            ),
          ],
        ),
        home: AppScope(controller: runtime.app, child: Scaffold(body: const AppShell())),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('модуль ставит экран при сборке приложения, до первого кадра', () async {
    // Стартовая команда модуля выполняется при установке — панели стоят на
    // экране ещё до того, как приложение начнёт читать каталоги.
    expect(
      runtime.app.view.contentAt(ViewportPosition.fullscreen),
      isNull,
      reason: 'панели видны, пока сверху ничего нет',
    );
  });

  test('фокус экрану панелей не нужен: активную панель знает приложение', () async {
    await runtime.app.start();

    expect(runtime.app.view.panelAt(ViewportPosition.left)?.takesKeyboard, isFalse);
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

    // Сторону панель выводит сама: вид её строит реестр, и про место в окне
    // ему знать неоткуда. Поэтому проверяется рамка — то, что нарисовано, — а
    // не аргумент, которого больше нет.
    final frames = tester.widgetList<FcPanelFrame>(find.byType(FcPanelFrame)).toList();

    expect(frames.first.outerEdge, PanelOuterEdge.left);
    expect(frames.last.outerEdge, PanelOuterEdge.right);
  });

  /// Рамка панели: тот `Container` внутри `FcPanelFrame`, который залит её
  /// фоном. Их там несколько — своя коробка есть и у плашки с путём.
  Border borderOf(WidgetTester tester, int index) {
    final frame = find.byType(FcPanelFrame).at(index);
    final boxes = tester.widgetList<Container>(find.descendant(of: frame, matching: find.byType(Container)));
    final panel = boxes.firstWhere(
      (box) => (box.decoration as BoxDecoration?)?.color == const DefaultColors().panelBackground,
    );
    return (panel.decoration! as BoxDecoration).border! as Border;
  }

  testWidgets('без полей внешние края открыты: рамке не от чего отделять', (tester) async {
    await runtime.app.start();
    await pumpScreen(tester, metrics: const _MetricsFlush());

    expect(borderOf(tester, 0).left.style, BorderStyle.none);
    expect(borderOf(tester, 1).right.style, BorderStyle.none);
    // Внутренние края на месте: там панели соседствуют друг с другом.
    expect(borderOf(tester, 0).right.style, BorderStyle.solid);
  });

  testWidgets('появились поля — рамка замыкается со всех сторон', (tester) async {
    await runtime.app.start();
    await pumpScreen(tester, metrics: const _MetricsWithSides());

    // Иначе в отступе видна открытая сторона панели.
    for (final index in [0, 1]) {
      final border = borderOf(tester, index);
      expect(border.left.style, BorderStyle.solid);
      expect(border.right.style, BorderStyle.solid);
    }
  });

  testWidgets('поля по краям окна отступают, а не только панели', (tester) async {
    await runtime.app.start();
    await pumpScreen(tester, metrics: const _MetricsWithSides());

    final window = tester.getRect(find.byType(AppShell));
    final panels = tester.getRect(find.byType(SplitView));

    expect(panels.left - window.left, 20);
    expect(window.right - panels.right, 20);

    // Ряд кнопок отступает вместе с панелями: он их подписывает и обязан
    // кончаться там же, где они.
    final bar = tester.getRect(find.byType(FunctionBar));
    expect(bar.left, panels.left);
    expect(bar.right, panels.right);
  });
}
