import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/keymaps.dart';
import 'package:flutter_test/flutter_test.dart';

/// Наборы клавиш: встроенные, свои, правка при наборе (`docs/spec/keymaps.md`,
/// `docs/spec/key-presets.md`).
void main() {
  late InMemoryTreeProvider provider;
  late AppRuntime runtime;
  late Keymaps keymaps;

  Keymaps keymapsOf(AppRuntime runtime) =>
      Keymaps(app: runtime.app, builtIn: () => runtime.resolve<KeymapCatalog>().keymaps);

  setUp(() async {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
      ..home = '/home';
    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
    keymaps = keymapsOf(runtime);
  });

  String? commandOn(String keys) => runtime.commands.commandFor(KeyCombination.parse(keys))?.id;

  KeyOverride bind(String binding, String key) => KeyOverride(binding: binding, key: key);

  test('оформление и клавиши стоят первыми, кто бы ни объявлялся раньше', () async {
    // Разделы идут по модулям, а первой устанавливается не оболочка, а
    // файловая система: без оговорки они вставали бы после неё.
    final full = await testApp(
      provider: provider,
      modules: appModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    addTearDown(full.dispose);

    final pages = full.resolve<SettingsCatalog>().pages;

    expect(pages.where((page) => page.priority != 0).map((page) => page.title), ['Appearance', 'Keyboard']);
    expect(pages.first.title, 'Appearance');
    expect(pages.map((page) => page.title), isNot(contains('Presets')), reason: 'раздел наборов убран');
  });

  test('в списке Default, встроенные, потом свои', () {
    expect(keymaps.names, ['', 'mc', 'far', 'Finder']);

    keymaps.saveAs('Моё');

    expect(keymaps.names, ['', 'mc', 'far', 'Finder', 'Моё']);
  });

  test('каждая запись встроенного набора находит свою привязку', () {
    // Иначе набор молча ничего не делает: достаточно переименовать привязку в
    // модуле (`docs/spec/key-presets.md`, §2).
    final names = {for (final binding in runtime.commands.declaredBindings) binding.id};

    for (final keymap in keymaps.builtIn) {
      for (final override in keymap.keys) {
        expect(
          names,
          contains(override.binding),
          reason: 'набор «${keymap.name}» целится в «${override.binding}», а такой привязки нет',
        );
      }
    }
  });

  test('набор mc применяется', () {
    keymaps.select('mc');

    expect(runtime.app.keymap, 'mc');
    expect(commandOn('Ctrl-R'), 'panel.reload');
    expect(commandOn('Alt-.'), 'panel.toggleHidden');
    expect(commandOn('Ins'), 'panel.selection.toggle');
    // Клавиша у дела одна: прежняя не остаётся висеть. Сравнивается сама
    // привязка — вне macOS `Cmd-R` и `Ctrl-R` это одно и то же сочетание.
    expect(runtime.commands.bindingsOf('panel.toggleHidden').single.keys.toString(), 'Alt-.');
  });

  test('набор Finder отдаёт пробел быстрому просмотру', () {
    keymaps.select('Finder');

    expect(commandOn('Space'), 'viewer.quickView');
    expect(commandOn('Ins'), 'panel.selection.toggle');
    expect(commandOn('Cmd-Bsp'), 'file.remove');
  });

  test('набор far меняет местами адрес и выбор вида', () {
    keymaps.select('far');

    expect(runtime.commands.bindingFor(KeyCombination.parse('Alt-F1'))?.id, 'panel.openPath.left');
    expect(runtime.commands.bindingFor(KeyCombination.parse('Cmd-F1'))?.id, 'panel.view.choose.left');
  });

  test('о чём набор молчит, то остаётся умолчанием', () {
    keymaps.select('mc');

    expect(commandOn('F5'), 'file.copy');
    expect(commandOn('F8'), 'file.remove');
  });

  test('правка остаётся при наборе, а не едет за выбором', () {
    keymaps.select('mc');
    runtime.app.setKeyOverrides([...runtime.app.keyOverrides, bind('file.copy', 'Ctrl-Shift-Y')]);

    keymaps.select('far');
    expect(commandOn('Ctrl-Shift-Y'), isNull, reason: 'правка mc уехала в far');

    keymaps.select('mc');
    expect(commandOn('Ctrl-Shift-Y'), 'file.copy', reason: 'правка mc потерялась');
  });

  test('Default помнит свою правку так же', () {
    runtime.app.setKeyOverrides([bind('file.copy', 'Ctrl-Shift-Y')]);

    keymaps.select('mc');
    keymaps.select(Keymaps.defaultName);

    expect(runtime.app.keyOverrides.single.key, 'Ctrl-Shift-Y');
  });

  test('New — копия нынешних клавиш под новым именем, выбрана', () {
    keymaps.select('mc');
    final keys = [...runtime.app.keyOverrides];

    expect(keymaps.saveAs('Моё'), isTrue);

    expect(runtime.app.keymap, 'Моё');
    expect(keymaps.own.single.keys.map((item) => item.binding), keys.map((item) => item.binding));
    expect(commandOn('Ctrl-R'), 'panel.reload');
  });

  test('имя встроенного и пустое заняты', () {
    expect(keymaps.saveAs('mc'), isFalse, reason: 'свой «mc» затёр бы встроенный');
    expect(keymaps.saveAs('  '), isFalse);
    expect(keymaps.freeName('mc'), 'mc 2');
  });

  test('правка своего набора пишется в него самого', () {
    keymaps.saveAs('Моё');
    runtime.app.setKeyOverrides([bind('file.copy', 'Ctrl-Shift-Y')]);

    keymaps.select('mc');

    expect(keymaps.own.single.keys.single.key, 'Ctrl-Shift-Y');
    expect(runtime.app.keymapEdits.containsKey('Моё'), isFalse);
  });

  test('встроенный не удалить', () {
    keymaps.select('mc');

    expect(keymaps.remove('mc'), isFalse);
    expect(keymaps.remove(Keymaps.defaultName), isFalse);
    expect(keymaps.names, contains('mc'));
  });

  test('удалили выбранный свой — выбран Default со своей правкой', () {
    runtime.app.setKeyOverrides([bind('file.copy', 'Ctrl-Shift-Y')]);
    keymaps.saveAs('Моё');
    runtime.app.setKeyOverrides([bind('file.remove', 'Ctrl-Shift-D')]);

    expect(keymaps.remove('Моё'), isTrue);

    expect(runtime.app.keymap, isEmpty);
    expect(keymaps.own, isEmpty);
    expect(runtime.app.keyOverrides.single.key, 'Ctrl-Shift-Y', reason: 'Default вернулся без своей правки');
  });

  test('удаление невыбранного выбора не трогает', () {
    keymaps.saveAs('Моё');
    keymaps.select('mc');

    keymaps.remove('Моё');

    expect(runtime.app.keymap, 'mc');
    expect(commandOn('Ctrl-R'), 'panel.reload');
  });

  test('возврат к началу: встроенный — к объявленному', () {
    keymaps.select('mc');
    final declared = keymaps.builtIn.firstWhere((item) => item.name == 'mc').keys;
    runtime.app.setKeyOverrides([bind('file.copy', 'Ctrl-Shift-Y')]);

    keymaps.resetCurrent();

    expect(runtime.app.keyOverrides.map((item) => item.key), declared.map((item) => item.key));
    expect(commandOn('Ctrl-R'), 'panel.reload');
  });

  test('возврат к началу: свой — к умолчаниям приложения', () {
    keymaps.select('mc');
    keymaps.saveAs('Моё');

    keymaps.resetCurrent();

    expect(runtime.app.keyOverrides, isEmpty);
  });

  test('незнакомый выбранный читается как Default', () {
    // Набор удалили в другом окне, модуль наборов выключили.
    runtime.app.setKeymaps(keymap: 'нет такого', keymaps: const [], edits: const {}, keys: const []);

    expect(keymaps.current, Keymaps.defaultName);
  });

  test('наборы и правки переживают перезапуск через файл', () async {
    final store = InMemorySettingsStore(settings: AppSettings.defaults('/home'));
    final first = await testApp(provider: provider, modules: featureModules(), store: store);
    await first.app.start();
    final mine = keymapsOf(first);
    mine.select('mc');
    first.app.setKeyOverrides([...first.app.keyOverrides, bind('file.copy', 'Ctrl-Shift-Y')]);
    mine.saveAs('Моё');
    first.app.setKeyOverrides([bind('file.remove', 'Ctrl-Shift-D')]);
    mine.select('far');
    await first.app.save();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restored = AppSettings.defaults('/home');
    extract(restored, jsonDecode(jsonEncode(serialize(store.saved!))));
    final second = await testApp(provider: provider, modules: featureModules(), settings: restored);
    await second.app.start();
    final again = keymapsOf(second);

    expect(again.current, 'far');
    expect(again.own.single.name, 'Моё');
    expect(again.own.single.keys.single.key, 'Ctrl-Shift-D');
    again.select('mc');
    expect(
      second.commands.commandFor(KeyCombination.parse('Ctrl-Shift-Y'))?.id,
      'file.copy',
      reason: 'правка mc не пережила перезапуск',
    );
  });
}
