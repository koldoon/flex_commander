import 'package:fc_api/fc_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок окна поиска: таблица находок в рамке, постоянного размера.
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

  testWidgets('окно поиска до первого поиска совпадает с эталоном', (tester) async {
    await appWith(tester);
    await openWindow(tester);

    // Пустая рамка на своём месте: сюда придут находки, и окно уже такого
    // размера, каким останется.
    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/find_files_empty.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('окно поиска с находками совпадает с эталоном', (tester) async {
    await appWith(tester);
    await openWindow(tester);

    // Поле именно этого окна: внизу экрана стоит ещё и командная строка.
    await tester.enterText(
      find.descendant(of: find.byType(FindFilesForm), matching: find.byType(EditableText)),
      '*.dart',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/find_files.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });
}
