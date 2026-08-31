import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок окна настроек: разделы по модулям, поля с подписями и прокрутка.
///
/// Обновление: `flutter test --update-goldens`.
void main() {
  testWidgets('окно настроек совпадает с эталоном', (tester) async {
    final provider = InMemoryTreeProvider([FakeEntry.directory('/Users'), FakeEntry.directory('/Users/koldoon')]);

    final settings = AppSettings(
      left: PanelSettings.defaults('/Users/koldoon'),
      right: PanelSettings.defaults('/Users'),
    );
    final app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/settings_dialog.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });
}
