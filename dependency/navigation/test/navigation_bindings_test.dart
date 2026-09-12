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
    expect(app.left.cursorIndex, app.left.entries.length - 1);

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

  group('история переходов', () {
    test('обе привычки ведут назад и вперёд', () async {
      await app.start();
      await app.left.openPath('/home/docs');
      await pumpEventQueue();

      expect(commands.commandFor(KeyCombination.parse('Cmd-['))?.id, GoBackCommand.commandId);
      expect(commands.commandFor(KeyCombination.parse('Alt-Left'))?.id, GoBackCommand.commandId);

      commands.dispatch(KeyCombination.parse('Cmd-['));
      await pumpEventQueue();
      expect(app.left.currentPath, '/home');

      expect(commands.commandFor(KeyCombination.parse('Cmd-]'))?.id, GoForwardCommand.commandId);
      commands.dispatch(KeyCombination.parse('Alt-Right'));
      await pumpEventQueue();
      expect(app.left.currentPath, '/home/docs');
    });

    test('идти некуда — команда приглушена, а не молчит', () async {
      await app.start();
      final where = app.left.currentPath;

      // Привязка находится и в начале пути — иначе ряду кнопок нечего было бы
      // показать, — но выполнить её нельзя, и нажатие ничего не делает.
      final back = commands.commandFor(KeyCombination.parse('Cmd-['));
      expect(back?.id, GoBackCommand.commandId);
      expect(commands.isExecutable(back!), isFalse, reason: 'из начала истории идти назад некуда');

      commands.dispatch(KeyCombination.parse('Cmd-['));
      await pumpEventQueue();
      expect(app.left.currentPath, where);

      final forward = commands.commandFor(KeyCombination.parse('Cmd-]'));
      expect(forward?.id, GoForwardCommand.commandId);
      expect(commands.isExecutable(forward!), isFalse, reason: 'вперёд некуда: не возвращались');
    });

    test('голые стрелки по-прежнему водят по списку', () async {
      await app.start();

      // `Left` и `Right` заняты переходом в начало и конец: сочетание с
      // модификатором до них не доходит, а без модификатора — их.
      expect(commands.commandFor(KeyCombination.parse('Left'))?.id, 'panel.cursor.first');
      expect(commands.commandFor(KeyCombination.parse('Right'))?.id, 'panel.cursor.last');
    });
  });

  test('пометка пробелом не перехвачена переходом к имени', () async {
    await app.start();
    // Курсор на «..» пометить нечего, и клавиша досталась бы первой попавшейся
    // привязке — проверяем на настоящем объекте.
    app.left.setCursorToName('notes.txt');

    expect(commands.commandFor(KeyCombination.parse('Space'))?.id, 'panel.selection.toggle');
    expect(commands.commandFor(const KeyCombination('D'))?.id, 'panel.goToName');
  });

  test('Shift-Space помечает, не сходя с места', () async {
    await app.start();
    app.left.setCursorToName('notes.txt');
    final at = app.left.cursorIndex;

    expect(commands.commandFor(KeyCombination.parse('Shift-Space'))?.id, 'panel.selection.toggleInPlace');

    commands.dispatch(KeyCombination.parse('Shift-Space'));
    await pumpEventQueue();

    expect(app.left.markedPaths, contains(app.left.entries[at].path));
    expect(app.left.cursorIndex, at, reason: 'курсор остался на помеченном');
  });

  test('в быстром поиске пробел набирается, а не помечает', () async {
    await app.start();
    app.left.setCursorToName('notes.txt');

    commands.run(QuickSearchCommand.commandId);

    // Пробел — такая же буква имени: «Program Files» иначе не наберёшь, а
    // полоса пропадала на середине слова.
    expect(commands.commandFor(KeyCombination.parse('Space'))?.id, 'panel.quickSearch.type');
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

    expect(app.left.currentPath, '/home');
    expect(
      {
        for (final entry in app.left.entries)
          if (app.left.isMarked(entry)) entry.name,
      },
      {'notes.txt'},
    );

    // Панель свободна — теперь Esc снимает пометку.
    commands.dispatch(KeyCombination.parse('Esc'));
    expect(app.left.markedPaths.isEmpty, isTrue);
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
