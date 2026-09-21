import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Переназначенные клавиши в собранном приложении
/// (`docs/spec/key-bindings.md`).
void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
      ..home = '/home';
  });

  Future<AppRuntime> build({List<KeyOverride>? keys, InMemorySettingsStore? store}) async {
    final settings = AppSettings(
      left: PanelSettings.defaults('/home'),
      right: PanelSettings.defaults('/home'),
      keys: keys,
    );
    final runtime = await testApp(
      provider: provider,
      modules: [const Navigation(), ...featureModules()],
      settings: settings,
      store: store,
    );
    await runtime.app.start();
    return runtime;
  }

  String? commandOn(AppRuntime runtime, String keys) => runtime.commands.commandFor(KeyCombination.parse(keys))?.id;

  test('переназначенная клавиша действует с самого запуска', () async {
    final runtime = await build(keys: [KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-C')]);

    expect(commandOn(runtime, 'Ctrl-Shift-C'), 'file.copy');
    expect(commandOn(runtime, 'F5'), isNot('file.copy'), reason: 'прежняя клавиша всё ещё копирует');
  });

  test('правка применяется сразу и переживает перезапуск', () async {
    final store = InMemorySettingsStore(settings: AppSettings.defaults('/home'));
    final runtime = await build(store: store);
    expect(commandOn(runtime, 'F5'), 'file.copy');

    runtime.app.setKeyOverrides([KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-C')]);
    await runtime.app.save();

    expect(commandOn(runtime, 'Ctrl-Shift-C'), 'file.copy', reason: 'клавиша не подействовала сразу');
    expect(store.saved?.keys.single.key, 'Ctrl-Shift-C', reason: 'выбор не доехал до настроек');

    // Перезапуск: те же настройки, новое приложение.
    final second = await testApp(
      provider: provider,
      modules: [const Navigation(), ...featureModules()],
      settings: store.saved,
    );
    await second.app.start();

    expect(second.commands.commandFor(KeyCombination.parse('Ctrl-Shift-C'))?.id, 'file.copy');
  });

  test('возврат умолчаний возвращает клавишу', () async {
    final runtime = await build(keys: [KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-C')]);

    runtime.app.setKeyOverrides([]);

    expect(commandOn(runtime, 'F5'), 'file.copy');
    expect(commandOn(runtime, 'Ctrl-Shift-C'), isNull);
  });

  test('у двух настраиваемых привязок не бывает одного имени', () async {
    // Имя — то, чем переназначение и набор целятся в дело
    // (`docs/spec/key-bindings.md`, §3). Два дела с одним именем означали бы,
    // что выбор человека попадает не туда; заодно это стережёт правило «одна
    // клавиша на дело».
    final runtime = await build();
    final seen = <String, KeyBinding>{};

    for (final binding in runtime.commands.declaredBindings) {
      if (binding.context == null) {
        continue;
      }
      final twin = seen[binding.id];
      expect(twin, isNull, reason: 'имя «${binding.id}» занято дважды: $twin и $binding');
      seen[binding.id] = binding;
    }
  });

  test('ряд кнопок и справка узнают новое сами', () async {
    final runtime = await build();
    var told = 0;
    runtime.commands.addListener(() => told++);

    runtime.app.setKeyOverrides([KeyOverride(binding: 'file.copy', key: 'Ctrl-Shift-C')]);

    expect(told, greaterThan(0), reason: 'реестр промолчал, и подписанные на него остались со старым');
    expect(runtime.commands.bindingsOf('file.copy').single.keys.toString(), 'Ctrl-Shift-C');
  });
}
