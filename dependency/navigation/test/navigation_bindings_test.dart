import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Клавиши модуля и то, как они уживаются друг с другом.
///
/// Раньше это проверялось на общем наборе команд приложения; теперь набор
/// собирается из модулей, и следить за ним нужно там, где он объявлен.
void main() {
  late InMemoryTreeProvider provider;
  late Application app;
  late CommandService commands;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
    ]);

    final runtime = await testApp(
      provider: provider,
      modules: [const Navigation()],
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    app = runtime.app;
    commands = runtime.commands;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('любую команду можно выполнить без клавиатуры', () async {
    await app.start();

    // Так команды будут вызываться из списка команд и из меню.
    expect(commands.run('panel.cursor.down'), isTrue);
    expect(app.left.cursorIndex, 1);

    expect(commands.run('panel.cursor.last'), isTrue);
    expect(app.left.cursorIndex, app.left.nodes.length - 1);

    expect(commands.run('panel.cursor.first'), isTrue);
    expect(app.left.cursorIndex, 0);

    expect(commands.run('app.togglePanel'), isTrue);
    expect(app.activePanel, same(app.right));
  });

  test('противоположные действия — разные команды', () {
    // Одна команда с параметром «направление» не подошла бы: из списка
    // команд её нельзя вызвать осмысленно.
    for (final id in [
      'panel.cursor.up',
      'panel.cursor.down',
      'panel.cursor.pageUp',
      'panel.cursor.pageDown',
      'panel.cursor.first',
      'panel.cursor.last',
      'panel.open',
      'panel.openWithSystem',
    ]) {
      expect(commands.find(id), isNotNull, reason: 'нет команды $id');
    }
  });

  test('пометка пробелом не перехвачена переходом к имени', () async {
    await app.start();

    expect(commands.commandFor(KeyCombination.parse('Space'))?.id, 'panel.selection.toggle');
    expect(commands.commandFor(const KeyCombination('D'))?.id, 'panel.goToName');
  });

  test('в быстром поиске буква достаётся ему, а не переходу к имени', () async {
    await app.start();

    commands.run(QuickSearchCommand.commandId);

    expect(commands.commandFor(const KeyCombination('D'))?.id, 'panel.quickSearch.type');
  });

  test('показ скрытых объектов доступен и на macOS', () {
    // `Cmd-H` на macOS забирает системное меню приложения, и до окна нажатие
    // не доходит: без второго сочетания команда была бы недоступна.
    expect(commands.commandFor(KeyCombination.parse('Cmd-Shift-H'))?.id, 'panel.toggleHidden');
    expect(commands.bindingsOf('panel.toggleHidden'), hasLength(2));
  });

  test('Esc во время чтения отменяет операцию, а не снимает пометку', () async {
    await app.start();

    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();

    // Пока панель занята, Esc должен доставаться команде отмены.
    final opening = app.left.openPath('/home/docs');
    expect(app.left.busy, isTrue);
    commands.dispatch(KeyCombination.parse('Esc'));
    await opening;

    expect(app.left.directory?.pathString, '/home');
    expect(app.left.selection.names, {'notes.txt'});

    // Панель свободна — теперь Esc снимает пометку.
    commands.dispatch(KeyCombination.parse('Esc'));
    expect(app.left.selection.isEmpty, isTrue);
  });

  test('приложение собирается и без модуля навигации', () async {
    final runtime = await testApp(provider: provider);

    // Ходить по дереву будет нечем, но запуск — не место для сюрпризов:
    // оболочка со справкой на месте, а команд навигации просто нет.
    expect(runtime.commands.find('panel.up'), isNull);
    expect(runtime.commands.find('app.help'), isNotNull);
    expect(runtime.app.left, isNotNull);
  });
}
