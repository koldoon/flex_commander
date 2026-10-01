import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_places/fc_places.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Места переживают перезапуск: тем же путём, что в приложении, — запись,
/// файл JSON, чтение при запуске.
void main() {
  setUp(() => PlacesSettings.visibleByDefault = true);
  tearDown(() => PlacesSettings.visibleByDefault = false);

  test('добавленное, переименованное и убранное — на месте после перезапуска', () async {
    final provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.directory('/work')])..home = '/home';
    final store = InMemorySettingsStore(settings: AppSettings.defaults('/home'));
    final first = await testApp(provider: provider, modules: featureModules(), store: store);
    await first.app.start();

    final places = first.app.moduleSettings(Places.moduleId).section(PlacesSettings.new);
    expect(places.places, hasLength(6));
    final state = first.app.view.contentAt(ViewportPosition.sidebar) as PlacesState?;
    expect(state, isNotNull);
    state!.add('/work');
    state.remove(0);
    state.startRename(0);
    state.commitRename('Стол');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Как файл: в JSON и обратно.
    final file = jsonDecode(jsonEncode(serialize(store.saved!)));
    final restored = AppSettings.defaults('/home');
    extract(restored, file);

    final second = await testApp(provider: provider, modules: featureModules(), settings: restored);
    await second.app.start();
    final back = second.app.moduleSettings(Places.moduleId).section(PlacesSettings.new);
    expect(back.places.map((place) => (place.address, place.name)), [
      ('~/Desktop', 'Стол'),
      ('~/Documents', null),
      ('~/Downloads', null),
      ('/Applications', null),
      ('/', null),
      ('/work', null),
    ]);
  });
}
