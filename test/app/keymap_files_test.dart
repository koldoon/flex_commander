import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/keymaps.dart';
import 'package:flutter_test/flutter_test.dart';

/// Выгрузка набора клавиш в файл и загрузка обратно
/// (`docs/spec/keymaps.md`, §4).
void main() {
  late InMemoryContentProvider provider;
  late AppRuntime runtime;
  late Keymaps keymaps;

  setUp(() async {
    provider = InMemoryContentProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/out')])
      ..home = '/home';
    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
    keymaps = Keymaps(app: runtime.app, builtIn: () => runtime.resolve<KeymapCatalog>().keymaps);
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
    await write('/home/out', 'keymap.json', '{"name":"Дом"}');

    expect(read('/home/out/keymap.json'), '{"name":"Дом"}');
  });

  test('имя с разделителем пути отвергается', () async {
    // Каталог называют полем рядом; уйти из него через имя файла — не то, о
    // чём человек просил.
    await expectLater(write('/home', 'out/keymap.json', '{}'), throwsA(isA<FsError>()));
    await expectLater(write('/home', '', '{}'), throwsA(isA<FsError>()));
  });

  test('несуществующий каталог — ошибка, а не молчание', () async {
    await expectLater(write('/home/nowhere', 'keymap.json', '{}'), throwsA(isA<FsError>()));
  });

  test('выгруженный набор читается обратно тем же', () async {
    keymaps.select('mc');
    final keymap = keymaps.capture('mc');

    await write('/home/out', 'keymap.json', '${const JsonEncoder.withIndent('  ').convert(serialize(keymap))}\n');
    final back = Keymap()..fromMap(jsonDecode(read('/home/out/keymap.json')) as Map<String, dynamic>);

    expect(back.name, 'mc');
    expect(back.keys.map((item) => item.key), keymap.keys.map((item) => item.key));
  });

  test('выгрузка невыбранного берёт его правку', () {
    keymaps.select('mc');
    runtime.app.setKeyOverrides([KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-Y')]);
    keymaps.select('far');

    expect(keymaps.capture('mc').keys.single.key, 'Ctrl-Shift-Y');
  });

  test('прочитанный набор встаёт в список под свободным именем и выбран', () {
    keymaps.saveAs('Дом');

    final given = keymaps.add(Keymap(name: 'Дом', keys: [KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-Y')]));

    expect(given, 'Дом 2');
    expect(keymaps.current, 'Дом 2');
    expect(keymaps.own.map((item) => item.name), ['Дом', 'Дом 2']);
    expect(runtime.app.keyOverrides.single.key, 'Ctrl-Shift-Y');
  });

  test('пришедший под именем встроенного не затирает его', () {
    expect(keymaps.add(Keymap(name: 'mc')), 'mc 2');
    expect(keymaps.builtIn.map((item) => item.name), contains('mc'));
  });
}
