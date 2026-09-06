import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок краткого вида: имена столбцами, слева — он, справа — таблица.
///
/// Обновление: `flutter test --update-goldens`.
void main() {
  testWidgets('краткий вид совпадает с эталоном', (tester) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/Users'),
      FakeEntry.directory('/Users/koldoon'),
      FakeEntry.directory('/Users/koldoon/Documents'),
      FakeEntry.directory('/Users/koldoon/Downloads'),
      for (var i = 1; i <= 20; i++)
        FakeEntry.file(
          '/Users/koldoon/note${'$i'.padLeft(2, '0')}.txt',
          size: i * 1024,
          modified: DateTime(2026, 9, 6),
        ),
    ]);

    final settings = AppSettings(
      left: PanelSettings(path: '/Users/koldoon', view: BriefView.viewId),
      right: PanelSettings.defaults('/Users/koldoon'),
    );
    final app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(802, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/panel_brief.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });
}
