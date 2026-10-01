import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_places/fc_places.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Прозрачная точка 1×1 — настоящий `png`, чтобы картинке было что разобрать.
final Uint8List _dot = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Значки системы — подставные: канала раннера в прогоне нет.
class _ProbeIcons implements SystemIcons {
  final List<String> asked = [];

  @override
  Future<Uint8List?> forPath(String path, {required int pixels}) async {
    asked.add(path);
    return _dot;
  }

  @override
  Future<Uint8List?> forExtension(String extension, {required int pixels}) async => null;

  @override
  Future<Uint8List?> forKind(SystemIconKind kind, {required int pixels}) async => _dot;
}

class _ProbeIconsModule implements FcFrontendModule {
  const _ProbeIconsModule(this.icons);

  final _ProbeIcons icons;

  @override
  String get id => 'test.systemIcons';

  @override
  String get title => 'Probe icons';

  @override
  void installFrontend(FrontendRegistry registry) => registry.service<SystemIcons>((services) => icons);
}

/// Значки мест — системные, когда включены «System icons»
/// (`docs/spec/favorites-sidebar.md`, §2).
void main() {
  setUp(() => PlacesSettings.visibleByDefault = true);
  tearDown(() => PlacesSettings.visibleByDefault = false);

  Future<_ProbeIcons> open(WidgetTester tester, {required bool system}) async {
    final probe = _ProbeIcons();
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/Desktop'),
      FakeEntry.directory('/Applications'),
    ])..home = '/home';
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    // Флаг модуля значков — по имени раздела: полосе он чужой.
    settings.modules.fromMap({
      'fc.icons': {'system': system},
      Places.moduleId: {
        'places': [
          {'address': '~'},
          {'address': '/Applications'},
          {'address': 'ssh://shark/home'},
          {'address': '/home/a.zip/inner'},
        ],
      },
    });
    final modules = [...featureModules().where((module) => module.id != 'fc.systemIcons'), _ProbeIconsModule(probe)];
    final app = (await testApp(provider: provider, modules: modules, settings: settings)).app;
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
    return probe;
  }

  Finder pictures() => find.descendant(of: find.byType(PlacesView), matching: find.byType(Image));

  testWidgets('включены — у мест на этой машине значок системы по пути', (tester) async {
    final probe = await open(tester, system: true);

    expect(probe.asked, containsAll(['/home', '/Applications']), reason: '~ развёрнут в домашний каталог');
    expect(
      probe.asked.where((path) => path.contains('shark') || path.contains('.zip')),
      isEmpty,
      reason: 'у сервера и архива пути этой машины нет',
    );
    expect(pictures(), findsNWidgets(2), reason: 'сервер и архив — своими глифами');
  });

  testWidgets('выключены — глифы мест, систему не спрашивают', (tester) async {
    final probe = await open(tester, system: false);

    expect(pictures(), findsNothing);
    expect(probe.asked, isEmpty);
  });
}
