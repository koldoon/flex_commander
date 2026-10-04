import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Снимок сжатого дерева: цепочки одиночных каталогов — одной строкой, голова
/// приглушена (`docs/spec/panel-view-compact-tree.md`).
///
/// Те же каталоги, что у снимка обычного дерева, и ещё глубокий путь до
/// исходников — на нём сжатие и видно.
///
/// Обновление: `flutter test --update-goldens`.
void main() {
  testWidgets('сжатое дерево совпадает с эталоном', (tester) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/Users'),
      FakeEntry.directory('/Users/koldoon'),
      FakeEntry.directory('/Users/koldoon/Documents'),
      FakeEntry.directory('/Users/koldoon/Downloads'),
      FakeEntry.directory('/Users/koldoon/Documents/notes'),
      FakeEntry.directory('/Users/koldoon/Documents/projects'),
      FakeEntry.directory('/Users/koldoon/Documents/projects/flex'),
      FakeEntry.directory('/Users/koldoon/Documents/projects/flex/lib'),
      FakeEntry.directory('/Users/koldoon/Documents/projects/flex/lib/src'),
      FakeEntry.file(
        '/Users/koldoon/Documents/projects/flex/lib/src/app.dart',
        size: 4096,
        modified: DateTime(2026, 9, 6),
      ),
      FakeEntry.file(
        '/Users/koldoon/Documents/projects/flex/lib/src/tree.dart',
        size: 8192,
        modified: DateTime(2026, 9, 6),
      ),
      FakeEntry.file('/Users/koldoon/Documents/report.txt', size: 2048, modified: DateTime(2026, 9, 6)),
      FakeEntry.file('/Users/koldoon/Documents/plan.md', size: 512, modified: DateTime(2026, 9, 6)),
      FakeEntry.file('/Users/koldoon/note.txt', size: 1024, modified: DateTime(2026, 9, 6)),
    ]);

    final settings = AppSettings(
      left: PanelSettings(path: '/Users/koldoon/Documents/projects/flex/lib/src', view: CompactTreeView.viewId),
      right: PanelSettings.defaults('/Users/koldoon'),
    );
    final app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(802, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/panel_compact_tree.png'));

    await tester.pump(const Duration(milliseconds: 20));
  });
}
