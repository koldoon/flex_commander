import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/presets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Встроенные наборы клавиш (`docs/spec/key-presets.md`).
void main() {
  late AppRuntime runtime;
  late Presets presets;

  setUp(() async {
    final provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
      ..home = '/home';
    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
    presets = Presets(
      app: runtime.app,
      catalog: () => runtime.resolve<SettingsCatalog>(),
      embedded: () => runtime.resolve<PresetCatalog>().presets,
    );
  });

  String? commandOn(String keys) => runtime.commands.commandFor(KeyCombination.parse(keys))?.id;

  test('три набора объявлены и стоят впереди своих', () {
    expect(presets.all.map((item) => item.name), ['mc', 'far', 'Finder']);

    presets.saveAs('Моё');

    expect(presets.all.map((item) => item.name), ['mc', 'far', 'Finder', 'Моё']);
  });

  test('каждая запись набора находит свою привязку', () {
    // Иначе набор молча ничего не делает: достаточно переименовать привязку в
    // модуле (`docs/spec/key-presets.md`, §2).
    final names = {for (final binding in runtime.commands.declaredBindings) binding.id};

    for (final preset in presets.all) {
      for (final override in preset.keys) {
        expect(
          names,
          contains(override.binding),
          reason: 'набор «${preset.name}» целится в «${override.binding}», а такой привязки нет',
        );
      }
    }
  });

  test('набор mc применяется', () {
    presets.select('mc');

    expect(commandOn('Ctrl-R'), 'panel.reload');
    expect(commandOn('Alt-.'), 'panel.toggleHidden');
    expect(commandOn('Ins'), 'panel.selection.toggle');
    // Клавиша у дела одна: прежняя не остаётся висеть. Сравнивается сама
    // привязка — вне macOS `Cmd-R` и `Ctrl-R` это одно и то же сочетание.
    expect(runtime.commands.bindingsOf('panel.toggleHidden').single.keys.toString(), 'Alt-.');
  });

  test('набор Finder отдаёт пробел быстрому просмотру', () {
    presets.select('Finder');

    expect(commandOn('Space'), 'viewer.quickView');
    expect(commandOn('Ins'), 'panel.selection.toggle');
    expect(commandOn('Cmd-Bsp'), 'file.remove');
  });

  test('набор far меняет местами адрес и выбор вида', () {
    presets.select('far');

    expect(runtime.commands.bindingFor(KeyCombination.parse('Alt-F1'))?.id, 'panel.openPath.left');
    expect(runtime.commands.bindingFor(KeyCombination.parse('Cmd-F1'))?.id, 'panel.view.choose.left');
  });

  test('о чём набор молчит, то остаётся умолчанием', () {
    presets.select('mc');

    expect(commandOn('F5'), 'file.copy');
    expect(commandOn('F8'), 'file.remove');
  });

  test('встроенный набор не обновить и не удалить', () {
    presets.select('mc');

    expect(presets.isEmbedded('mc'), isTrue);
    expect(presets.updateCurrent(), isFalse);
    expect(presets.remove('mc'), isFalse);
    expect(presets.all.map((item) => item.name), contains('mc'));
  });

  test('имя встроенного занято навсегда', () {
    expect(presets.saveAs('mc'), isFalse, reason: 'свой «mc» затёр бы встроенный');
    expect(presets.freeName('mc'), 'mc 2');
  });

  test('выбранный набор переживает перезапуск', () async {
    presets.select('far');
    await runtime.app.save();

    expect(runtime.app.preset, 'far');
  });
}
