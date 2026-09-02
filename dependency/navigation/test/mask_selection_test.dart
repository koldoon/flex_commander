import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Пометка по маске: `+` помечает, `-` снимает.
void main() {
  late AppRuntime runtime;
  late AppController app;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/src.d'),
      FakeEntry.file('/home/main.dart', size: 1),
      FakeEntry.file('/home/util.dart', size: 1),
      FakeEntry.file('/home/readme.md', size: 1),
      FakeEntry.file('/home/photo.PNG', size: 1),
      FakeEntry.file('/home/main.dart.bak', size: 1),
    ]);
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    runtime = await testApp(provider: provider, modules: [const Navigation()], settings: settings);
    app = runtime.app;
    await app.start();
  });

  SelectByMaskCommand select() => app.commands.create('panel.selection.selectByMask')! as SelectByMaskCommand;

  DeselectByMaskCommand deselect() => app.commands.create('panel.selection.deselectByMask')! as DeselectByMaskCommand;

  Future<void> mark(String mask) => select().executeWith({MaskSelectionCommandBase.maskParam: mask});

  Future<void> unmark(String mask) => deselect().executeWith({MaskSelectionCommandBase.maskParam: mask});

  Set<String> marked() => app.left.selection.names;

  test('помечает совпавшее', () async {
    await mark('*.dart');

    expect(marked(), {'main.dart', 'util.dart'});
  });

  test('пометка дополняется, а не заменяется', () async {
    await mark('*.dart');
    await mark('*.md');

    expect(marked(), {'main.dart', 'util.dart', 'readme.md'});
  });

  test('снимает только совпавшее', () async {
    await mark('*');
    await unmark('*.dart');

    expect(marked(), isNot(contains('main.dart')));
    expect(marked(), contains('readme.md'));
    expect(marked(), contains('src.d'), reason: 'каталог тоже помечается маской «*»');
  });

  test('«..» не помечается никакой маской', () async {
    await app.left.openPath('/home/src.d');
    await mark('*');

    expect(marked(), isNot(contains('..')));
  });

  test('регистр не важен', () async {
    await mark('*.png');

    expect(marked(), {'photo.PNG'});
  });

  test('исключения работают', () async {
    await mark('*.dart;!*.bak');

    expect(marked(), {'main.dart', 'util.dart'});
  });

  test('применённая маска запоминается — свежая впереди', () async {
    await mark('*.dart');
    await mark('*.md');

    final remembered = app.moduleSettings('fc.navigation').section(NavigationSettings.new).recentMasks;
    expect(remembered.take(2), ['*.md', '*.dart']);
  });

  test('«+» открывает окно маски', () {
    expect(runtime.commands.dispatch(KeyCombination.parse('+')), isTrue);
    expect(app.view.dialogs, hasLength(1));
  });

  test('«Shift-=» — то же самое: на основной клавиатуре мака «+» только так и набирается', () {
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-=')), isTrue);
    expect(app.view.dialogs, hasLength(1));
  });

  test('«-» открывает окно, только когда есть что снимать', () async {
    // Пустая пометка — команда неисполнима, и клавиша достаётся быстрому
    // поиску, который стоит в списке ниже.
    expect(deselect().isExecutable(CommandContext.of(app)), isFalse);
    runtime.commands.dispatch(KeyCombination.parse('-'));
    expect(app.view.dialogs, isEmpty);

    await mark('*.dart');

    expect(runtime.commands.dispatch(KeyCombination.parse('-')), isTrue);
    expect(app.view.dialogs, hasLength(1));
  });
}
