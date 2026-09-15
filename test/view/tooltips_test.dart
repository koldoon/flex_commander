import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подсказка не мешает мыши: она гаснет на нажатии и не всплывает посреди
/// жеста (`docs/spec/tooltips.md`, §5).
void main() {
  /// Имена заведомо длиннее колонки: подсказка у каждой строки есть — весь
  /// вопрос в том, всплывает ли она.
  String nameAt(int index) => 'невероятно длинное имя файла номер ${index.toString().padLeft(2, '0')}.txt';

  late AppController app;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      for (var i = 0; i < 12; i++) FakeEntry.file('/home/${nameAt(i)}', size: 1),
    ])..home = '/home';

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1312, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Строка **левой** панели по имени: в правой открыт тот же каталог.
  Finder row(int index) => find.descendant(
    of: find.byType(FileTable).first,
    matching: find.byWidgetPredicate((widget) => widget is FileTableRow && widget.entry.name == nameAt(index)),
  );

  /// Всплывшая подсказка — она одна на приложение.
  Finder shown() => find.byKey(FcTooltip.viewKey);

  testWidgets('навёл и подержал — имя договорилось', (tester) async {
    await pumpApp(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());

    await mouse.moveTo(tester.getCenter(row(3)));
    await tester.pump();
    expect(shown(), findsNothing, reason: 'мышь могла просто проезжать мимо');

    await tester.pump(FcTooltip.delay);
    expect(shown(), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('пометка правой кнопкой подсказок не заводит', (tester) async {
    await pumpApp(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: tester.getCenter(row(0)));
    await tester.pump();

    await mouse.down(tester.getCenter(row(0)));
    await tester.pump(const Duration(milliseconds: 20));

    // Строки едут под курсором, наведение приходит и с зажатой кнопкой.
    for (var index = 1; index < 8; index++) {
      await mouse.moveTo(tester.getCenter(row(index)));
      await tester.pump(FcTooltip.delay);
      expect(shown(), findsNothing, reason: 'посреди пометки подсказок не бывает');
    }

    await mouse.up();
    await tester.pumpAndSettle();

    expect(app.left.markedPaths.length, 8, reason: 'сама пометка при этом сработала');

    await disposeScreen(tester);
  });

  testWidgets('подсказка всплыла — нажатие её гасит, и до отпускания не возвращает', (tester) async {
    await pumpApp(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());

    await mouse.moveTo(tester.getCenter(row(2)));
    await tester.pump(FcTooltip.delay);
    expect(shown(), findsOneWidget);

    // Так начинается перетаскивание файла: нажали и повели.
    await mouse.down(tester.getCenter(row(2)));
    await tester.pump();
    expect(shown(), findsNothing);

    await mouse.moveTo(tester.getCenter(row(5)));
    await tester.pump(FcTooltip.delay);
    expect(shown(), findsNothing, reason: 'жест ещё идёт');

    await mouse.up();
    await tester.pumpAndSettle();

    // Отпустили — и подсказка снова работает: движение заводит отсчёт заново.
    await mouse.moveTo(tester.getCenter(row(6)));
    await tester.pump(FcTooltip.delay);
    expect(shown(), findsOneWidget);

    await disposeScreen(tester);
  });
}
