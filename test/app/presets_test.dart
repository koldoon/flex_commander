import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/presets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Наборы выбора: сбор, применение и хранение
/// (`docs/spec/settings-presets.md`).
void main() {
  late InMemoryTreeProvider provider;
  late AppRuntime runtime;
  late Presets presets;

  setUp(() async {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
      ..home = '/home';
    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
    presets = Presets(app: runtime.app, catalog: () => runtime.resolve<SettingsCatalog>());
  });

  /// Поле схемы — то самое, которым его правит окно. Ищется по модулю и
  /// ключу: `wordWrap` есть и у просмотрщика, и у редактора.
  SettingsField fieldOf(String module, String id) => [
    // Разделов у модуля бывает несколько: оболочка объявляет и свой, и наборы.
    for (final page in runtime.resolve<SettingsCatalog>().pages)
      if (page.id == module) ...page.build().fields,
  ].firstWhere((field) => field.id == id);

  test('раздел наборов стоит первым, кто бы ни объявлялся раньше', () async {
    // Разделы идут по модулям, а первым устанавливается не оболочка, а
    // файловая система: без оговорки наборы вставали после неё.
    final full = await testApp(
      provider: provider,
      modules: appModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    addTearDown(full.dispose);

    final pages = full.resolve<SettingsCatalog>().pages;

    expect(pages.first.title, 'Presets');
    // Приоритет поднимает просившего, а не перетасовывает соседей: у прочих он
    // нулевой, и стоят они там же, где их объявили. Просят место двое: набор
    // решает всё, что стоит ниже, а оформление идёт следом за ним
    // (`docs/spec/theme-editor.md`, §2).
    expect(pages.where((page) => page.priority != 0).map((page) => page.title), [
      'Presets',
      'Themes',
    ], reason: 'место просят только наборы и оформление');
  });

  test('снимок берёт выбор и не берёт память', () {
    final preset = presets.capture('Работа');

    // Выбор — в наборе.
    expect(preset.valueOf('fc.shell', 'themeId'), isNotNull);
    expect(preset.valueOf('fc.terminal', 'shell'), isNotNull);

    // Память — нет: ни путей панелей, ни геометрии окна, ни истории команд.
    final everything = {for (final section in preset.settings.values) ...section.keys};
    expect(everything, isNot(contains('path')));
    expect(everything, isNot(contains('window')));
    expect(everything, isNot(contains('recentCommands')));
    expect(everything, isNot(contains('history')));
  });

  test('свой выбор набор в себя не кладёт', () {
    // Набор, помнящий, какой набор выбран, — это петля.
    expect(presets.capture('Работа').valueOf('fc.shell', 'preset'), isNull);
  });

  test('у каждого поля, кроме кнопок и клавиш, значение есть', () {
    // Иначе поле молча выпало бы из набора и сбрасывалось к умолчанию на
    // каждое применение.
    for (final page in runtime.resolve<SettingsCatalog>().pages) {
      for (final field in page.build().fields) {
        if (field is SettingsButton || field is SettingsKeys) {
          continue;
        }
        expect(field.value, isNotNull, reason: 'поле «${field.title}» в набор не попадёт');
      }
    }
  });

  test('применение делает «ровно так»', () {
    final wrap = fieldOf('fc.text_viewer', 'wordWrap');
    final was = wrap.value;

    // Набор сложен на умолчаниях; потом поле трогают.
    presets.saveAs('Умолчания');
    wrap.apply(!(was! as bool));
    expect(wrap.value, isNot(was));

    presets.select('Умолчания');

    expect(wrap.value, was, reason: 'набор не вернул поле');
  });

  test('о чём набор молчит, то остаётся как было', () {
    final wrap = fieldOf('fc.text_viewer', 'wordWrap');
    final was = wrap.value! as bool;

    // Набор без этого поля вовсе — так выглядит набор клавиш: он о настройках
    // не говорит ничего (`docs/spec/settings-presets.md`, §4).
    final keysOnly = Preset(name: 'Только клавиши', keys: [KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-C')]);
    wrap.apply(!was);

    presets.apply(keysOnly);

    expect(wrap.value, !was, reason: 'набор тронул то, о чём молчал');
    expect(runtime.commands.bindingsOf('file.copy').single.keys.toString(), 'Ctrl-Shift-C');
  });

  test('накладка не сносит чужих переназначений', () {
    runtime.app.setKeyOverrides([KeyOverride(binding: 'file.move', key: 'Ctrl-Shift-M')]);

    presets.apply(Preset(name: 'mc', keys: [KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-C')]));

    expect(runtime.commands.bindingsOf('file.move').single.keys.toString(), 'Ctrl-Shift-M');
    expect(runtime.commands.bindingsOf('file.copy').single.keys.toString(), 'Ctrl-Shift-C');
  });

  test('клавиши едут набором', () {
    runtime.app.setKeyOverrides([KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-C')]);
    presets.saveAs('С клавишей');
    runtime.app.setKeyOverrides([]);

    presets.select('С клавишей');

    expect(runtime.app.keyOverrides.single.key, 'Ctrl-Shift-C');
    expect(runtime.commands.bindingsOf('file.copy').single.keys.toString(), 'Ctrl-Shift-C');
  });

  test('список едет набором и переживает запись', () {
    final extensions = fieldOf('fc.shell', 'compoundExtensions');
    extensions.apply(['tar.gz', 'cfg.json']);
    presets.saveAs('Дом');
    extensions.apply(<String>[]);

    presets.select('Дом');

    expect(extensions.value, ['tar.gz', 'cfg.json']);

    // И через файл: набор возят между машинами, и список обязан пережить
    // разбор наравне с флажком и числом.
    final back = Preset()..fromMap(serialize(presets.find('Дом')!) as Map<String, dynamic>);
    expect(back.valueOf('fc.shell', 'compoundExtensions'), ['tar.gz', 'cfg.json']);
  });

  test('испорченный список в наборе пропускается молча', () {
    // Набор мог прийти из другого выпуска, где это поле было строкой: падать
    // на нём незачем, а ставить — тем более.
    final alien =
        Preset()..fromMap({
          'name': 'Чужой',
          'settings': {
            'fc.shell': {
              'compoundExtensions': [1, 2],
            },
          },
        });

    expect(alien.valueOf('fc.shell', 'compoundExtensions'), isNull);

    final extensions = fieldOf('fc.shell', 'compoundExtensions');
    extensions.apply(['tar.gz']);
    extensions.apply('tar.gz; cfg.json');

    expect(extensions.value, ['tar.gz'], reason: 'строка списком не стала');
  });

  test('занятое имя не заводит второго набора', () {
    expect(presets.saveAs('Дом'), isTrue);
    expect(presets.saveAs('Дом'), isFalse, reason: 'второй «Дом» затёр бы первый');
    expect(presets.all, hasLength(1));
  });

  test('пришедший со стороны набор получает свободное имя', () {
    presets.saveAs('Дом');

    final name = presets.add(Preset(name: 'Дом'));

    expect(name, 'Дом 2');
    expect(presets.all.map((item) => item.name), ['Дом', 'Дом 2']);
    expect(presets.current, 'Дом 2');
  });

  test('«обновить» переписывает выбранный сделанным', () {
    final wrap = fieldOf('fc.text_viewer', 'wordWrap');
    final was = wrap.value! as bool;
    presets.saveAs('Дом');
    wrap.apply(!was);

    expect(presets.updateCurrent(), isTrue);
    wrap.apply(was);
    presets.select('Дом');

    expect(wrap.value, !was, reason: 'обновление не сохранило сделанного');
  });

  test('удаление снимает выбор, но настроек не трогает', () {
    final wrap = fieldOf('fc.text_viewer', 'wordWrap');
    presets.saveAs('Дом');
    final was = wrap.value;

    expect(presets.remove('Дом'), isTrue);

    expect(presets.all, isEmpty);
    expect(presets.current, isEmpty);
    expect(wrap.value, was, reason: 'удаление набора не должно трогать настройки');
  });

  test('«None» ничего не применяет', () {
    final wrap = fieldOf('fc.text_viewer', 'wordWrap');
    presets.saveAs('Дом');
    wrap.apply(!(wrap.value! as bool));
    final touched = wrap.value;

    presets.select('');

    expect(presets.current, isEmpty);
    expect(wrap.value, touched, reason: 'снятие выбора стёрло сделанное');
  });

  test('наборы доезжают до настроек', () {
    presets.saveAs('Дом');

    expect(runtime.app.settings.presets.single.name, 'Дом');
    expect(runtime.app.settings.preset, 'Дом');
  });
}
