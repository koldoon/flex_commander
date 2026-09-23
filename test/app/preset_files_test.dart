import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/presets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Выгрузка набора в файл и загрузка обратно
/// (`docs/spec/settings-presets.md`, §7–8).
void main() {
  late InMemoryContentProvider provider;
  late AppRuntime runtime;
  late Presets presets;

  setUp(() async {
    provider = InMemoryContentProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/out')])
      ..home = '/home';
    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
    presets = Presets(app: runtime.app, catalog: () => runtime.resolve<SettingsCatalog>());
  });

  /// Записать текст работой ядра — той самой, которой пишет выгрузка.
  Future<void> write(String folder, String name, String text) => runtime.app.runOperation().run(
    OperationSpec(
      kind: FileOperations.writeText,
      destination: Destination.path(folder),
      options: {FileOperations.name: name, FileOperations.text: text},
    ),
  );

  String read(String path) => utf8.decode(provider.entryAt(path)!.content);

  test('работа ядра создаёт файл с содержимым', () async {
    await write('/home/out', 'preset.json', '{"name":"Дом"}');

    expect(read('/home/out/preset.json'), '{"name":"Дом"}');
  });

  test('имя с разделителем пути отвергается', () async {
    // Каталог называют полем рядом; уйти из него через имя файла — не то, о
    // чём человек просил.
    await expectLater(write('/home', 'out/preset.json', '{}'), throwsA(isA<FsError>()));
    await expectLater(write('/home', '', '{}'), throwsA(isA<FsError>()));
  });

  test('несуществующий каталог — ошибка, а не молчание', () async {
    await expectLater(write('/home/nowhere', 'preset.json', '{}'), throwsA(isA<FsError>()));
  });

  test('выгруженный набор читается обратно тем же', () async {
    presets.saveAs('Дом');
    final preset = presets.find('Дом')!;

    await write('/home/out', 'preset.json', '${const JsonEncoder.withIndent('  ').convert(serialize(preset))}\n');
    final back = Preset()..fromMap(jsonDecode(read('/home/out/preset.json')) as Map<String, dynamic>);

    expect(back.name, 'Дом');
    expect(back.settings, preset.settings);
  });

  test('прочитанный набор встаёт в список под свободным именем', () {
    presets.saveAs('Дом');

    final given = presets.add(
      Preset(
        name: 'Дом',
        settings: {
          'fc.shell': {'themeId': 'dark'},
        },
      ),
    );

    expect(given, 'Дом 2');
    expect(presets.current, 'Дом 2');
    expect(presets.all.map((item) => item.name), ['Дом', 'Дом 2']);
  });
}
