import 'package:fc_api/fc_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимки обеих фаз окна поиска: сперва спрашивают, потом показывают.
///
/// Обновление: `flutter test --update-goldens`.
void main() {
  Future<AppController> appWith(WidgetTester tester) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/Users'),
      FakeEntry.directory('/Users/koldoon'),
      FakeEntry.directory('/Users/koldoon/Developer'),
      FakeEntry.directory('/Users/koldoon/Developer/lib'),
      FakeEntry.directory('/Users/koldoon/Developer/lib/src'),
      FakeEntry.directory('/Users/koldoon/Documents'),
      FakeEntry.file('/Users/koldoon/Developer/main.dart', size: 1200),
      FakeEntry.file('/Users/koldoon/Developer/lib/app.dart', size: 3400),
      FakeEntry.file('/Users/koldoon/Developer/lib/src/panel.dart', size: 8800),
      FakeEntry.file('/Users/koldoon/Developer/lib/src/viewport.dart', size: 5100),
      FakeEntry.file('/Users/koldoon/Developer/readme.md', size: 900),
    ]);
    final settings = AppSettings(
      left: PanelSettings.defaults('/Users/koldoon/Developer'),
      right: PanelSettings.defaults('/Users/koldoon/Documents'),
    );
    final app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> openWindow(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('окно параметров совпадает с эталоном', (tester) async {
    await appWith(tester);
    await openWindow(tester);

    // Раскладка `mc`: подписи над полями, два столбца, нереализованное
    // приглушено. Отступы и зазоры — общие для всех окон: своих рамок и своих
    // полей у окна поиска нет.
    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/find_files_params.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('окно находок совпадает с эталоном', (tester) async {
    await appWith(tester);
    await openWindow(tester);

    // Поле маски: в окне есть ещё два, приглушённых, и командная строка внизу
    // экрана. Живое поле здесь одно.
    await tester.enterText(
      find.descendant(
        of: find.byType(FindFilesForm),
        matching: find.byWidgetPredicate((widget) => widget is TextField && widget.enabled != false),
      ),
      '*.dart',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/find_files.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });
}
