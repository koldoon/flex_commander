import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок окна команды: форма из полей, где выключенное поле остаётся полем.
///
/// Обновление: `flutter test --update-goldens`.
void main() {
  testWidgets('окно копирования совпадает с эталоном', (tester) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/Users'),
      FakeEntry.directory('/Users/koldoon'),
      FakeEntry.directory('/Users/koldoon/Developer'),
      FakeEntry.directory('/Users/koldoon/Documents'),
      FakeEntry.file('/Users/koldoon/Developer/KEYS', size: 92262, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/LICENSE', size: 15258, modified: DateTime(2018, 2, 19)),
    ]);

    final settings = AppSettings(
      left: PanelSettings.defaults('/Users/koldoon/Developer'),
      right: PanelSettings.defaults('/Users/koldoon/Documents'),
    );
    final app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();

    app.left.setCursorToName('LICENSE');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/copy_dialog.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });
}
