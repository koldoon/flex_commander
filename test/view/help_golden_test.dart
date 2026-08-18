import 'dart:io';

import 'package:flex_commander/app.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

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

    final settingsPath = p.join(Directory.systemTemp.path, 'flex_commander_golden', 'help.json');
    final settings = AppSettings(
      left: PanelSettings.defaults('/Users/koldoon/Developer'),
      right: PanelSettings.defaults('/Users/koldoon'),
    );
    final app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: settingsPath),
      settings: settings,
      commands: defaultCommandRegistry(),
      saveDelay: const Duration(milliseconds: 5),
    );

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/help_dialog.png'));

    await tester.pump(const Duration(milliseconds: 20));
    app.dispose();
  });
}
