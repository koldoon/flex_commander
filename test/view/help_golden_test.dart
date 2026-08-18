import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок окна справки: таблица во всю высоту с полями от краёв экрана.
///
/// Обновление: `flutter test --update-goldens`.
void main() {
  testWidgets('окно справки совпадает с эталоном', (tester) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/Users'),
      FakeEntry.directory('/Users/koldoon'),
      FakeEntry.directory('/Users/koldoon/Developer'),
      FakeEntry.file('/Users/koldoon/Developer/KEYS', size: 92262, modified: DateTime(2018, 2, 19)),
    ]);

    final settings = AppSettings(
      left: PanelSettings.defaults('/Users/koldoon/Developer'),
      right: PanelSettings.defaults('/Users/koldoon'),
    );
    final app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/help_dialog.png'));

    // Приложение закрывает сам testApp: отложенной записи настроек даём
    // сработать, чтобы таймер не пережил тест.
    await tester.pump(const Duration(milliseconds: 20));
  });
}
