import 'dart:io';

import 'package:flex_commander/app.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Снимок окна в размере макета (802×621), чтобы вёрстку можно было сравнить
/// с `docs/design/design.png` глазами.
///
/// Обновление: `flutter test --update-goldens`.
void main() {
  testWidgets('окно целиком совпадает с эталоном', (tester) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/Users'),
      FakeEntry.directory('/Users/koldoon'),
      FakeEntry.directory('/Users/koldoon/Developer'),
      FakeEntry.directory('/Users/koldoon/Developer/bin'),
      FakeEntry.directory('/Users/koldoon/Developer/etc'),
      FakeEntry.directory('/Users/koldoon/Developer/lib'),
      FakeEntry.directory('/Users/koldoon/Developer/manual'),
      FakeEntry.file('/Users/koldoon/Developer/CONTRIBUTORS.xlsx', size: 6144, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/INSTALL', size: 126, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/KEYS', size: 92262, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/LICENSE', size: 15258, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/fetch.xml', size: 11366, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/Users/koldoon/Developer/patch.xml', size: 1946, modified: DateTime(2018, 2, 19)),
    ]);

    // Каталог настроек не создаётся: реальный ввод-вывод внутри тела
    // widget-теста подвешивает его поддельное асинхронное окружение.
    final settingsPath = p.join(Directory.systemTemp.path, 'flex_commander_golden', 'settings.json');
    const path = '/Users/koldoon/Developer';
    final settings = AppSettings(left: PanelSettings.defaults(path), right: PanelSettings.defaults(path));
    final app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: settingsPath),
      settings: settings,
      saveDelay: const Duration(milliseconds: 5),
    );

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app, navigatorKey: GlobalKey<NavigatorState>()));
    await app.start();
    await tester.pumpAndSettle();

    // Курсор в активной панели и пара помеченных объектов в пассивной —
    // на снимке должны быть видны все состояния строки.
    app.left.setCursorToName('INSTALL');
    app.right.selection.addAll(app.right.nodes.where((node) => node.name == 'LICENSE' || node.name == 'fetch.xml'));
    await tester.pump();

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/application_view.png'));

    await tester.pump(const Duration(milliseconds: 20));
    app.dispose();
  });
}
