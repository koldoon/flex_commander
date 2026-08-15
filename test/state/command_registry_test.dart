import 'dart:io';

import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/app_command.dart';
import 'package:flex_commander/state/commands/command_registry.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/commands/key_combination.dart';
import 'package:flex_commander/state/commands/navigation_commands.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Команда-заглушка, которая запоминает, что её вызвали.
class RecordingCommand extends AppCommand {
  RecordingCommand({required this.id, bool executable = true, this.label = 'Recording'}) : _executable = executable;

  @override
  final String id;

  @override
  final String label;

  final bool _executable;

  int calls = 0;
  List<String> lastTargets = const [];

  @override
  bool isExecutable(CommandContext context) => _executable;

  @override
  Future<void> execute(CommandContext context) async {
    calls++;
    lastTargets = context.targets.map((node) => node.name).toList();
  }
}

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;

  /// Не каждому тесту нужно приложение: чистые проверки набора команд
  /// обходятся без него, и завершение теста не должно на этом спотыкаться.
  var appBuilt = false;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
      FakeEntry.file('/home/setup.app', size: 30),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_commands');
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    if (appBuilt) {
      app.dispose();
      appBuilt = false;
    }
    await temp.delete(recursive: true);
  });

  AppController build(CommandRegistry registry) {
    appBuilt = true;
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home/docs'));
    return app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      commands: registry,
      saveDelay: const Duration(milliseconds: 5),
    );
  }

  group('разбор нажатия', () {
    test('выполняется первая подходящая команда', () async {
      final first = RecordingCommand(id: 'first');
      final second = RecordingCommand(id: 'second');
      final registry = CommandRegistry([first, second], [KeyBinding('F5', 'first'), KeyBinding('F5', 'second')]);
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F5')), isTrue);
      expect(first.calls, 1);
      expect(second.calls, 0);
    });

    test('невыполнимая команда пропускается', () async {
      final blocked = RecordingCommand(id: 'blocked', executable: false);
      final fallback = RecordingCommand(id: 'fallback');
      final registry = CommandRegistry(
        [blocked, fallback],
        [KeyBinding('F5', 'blocked'), KeyBinding('F5', 'fallback')],
      );
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F5')), isTrue);
      expect(blocked.calls, 0);
      expect(fallback.calls, 1);
    });

    test('нажатие без команды остаётся необработанным', () {
      final registry = CommandRegistry([RecordingCommand(id: 'a')], [KeyBinding('F5', 'a')]);
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F6')), isFalse);
    });

    test('несколько привязок вызывают команду одинаково', () {
      final command = RecordingCommand(id: 'multi');
      final registry = CommandRegistry([command], [KeyBinding('F5', 'multi'), KeyBinding('Cmd-E', 'multi')]);
      build(registry);

      registry.dispatch(KeyCombination.parse('F5'));
      registry.dispatch(KeyCombination.parse('Cmd-E'));

      // Команда не знает, чем её вызвали: обе привязки дают один и тот же вызов.
      expect(command.calls, 2);
    });

    test('фильтр по имени выбирает специализированную команду', () async {
      final apps = RecordingCommand(id: 'open.app');
      final common = RecordingCommand(id: 'open');
      final registry = CommandRegistry(
        [apps, common],
        [KeyBinding('Enter', 'open.app', nameMatch: RegExp(r'\.app$')), KeyBinding('Enter', 'open')],
      );
      build(registry);
      await app.start();

      app.left.setCursorToName('notes.txt');
      registry.dispatch(KeyCombination.parse('Enter'));
      expect(apps.calls, 0);
      expect(common.calls, 1);

      app.left.setCursorToName('setup.app');
      registry.dispatch(KeyCombination.parse('Enter'));
      expect(apps.calls, 1);
      expect(common.calls, 1);
    });
  });

  group('условия команды', () {
    test('без пометки целью становится объект под курсором', () async {
      final command = RecordingCommand(id: 'targets');
      build(CommandRegistry([command], [KeyBinding('F5', 'targets')]));
      await app.start();

      app.left.setCursorToName('notes.txt');
      app.commands.dispatch(KeyCombination.parse('F5'));

      expect(command.lastTargets, ['notes.txt']);
    });

    test('с пометкой целями становятся помеченные объекты', () async {
      final command = RecordingCommand(id: 'targets');
      build(CommandRegistry([command], [KeyBinding('F5', 'targets')]));
      await app.start();

      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();
      app.left.toggleCurrentMark();
      app.commands.dispatch(KeyCombination.parse('F5'));

      expect(command.lastTargets, ['notes.txt', 'report.xlsx']);
    });

    test('контекст берёт активную панель, а пассивная — приёмник', () async {
      final command = RecordingCommand(id: 'ctx');
      final registry = CommandRegistry([command], [KeyBinding('F5', 'ctx')]);
      build(registry);
      await app.start();

      app.toggleActivePanel();
      final context = registry.contextFor(command);

      expect(context.panel, app.right);
      expect(context.target, app.left);
    });
  });

  group('нижняя панель — та же клавиатура', () {
    test('кнопка находит команду по её привязке к клавише', () {
      final copy = RecordingCommand(id: 'copy', label: 'Copy');
      final registry = CommandRegistry([copy], [KeyBinding('F5', 'copy')]);
      build(registry);

      // Команда не объявляет, где её показывать: панель спрашивает,
      // что закреплено за F5.
      expect(registry.commandFor(KeyCombination.parse('F5')), copy);
      expect(registry.commandFor(KeyCombination.parse('F6')), isNull);
    });

    test('нажатие кнопки равносильно нажатию клавиши', () {
      final command = RecordingCommand(id: 'copy');
      final registry = CommandRegistry([command], [KeyBinding('F5', 'copy')]);
      build(registry);

      registry.dispatch(KeyCombination.parse('F5'));
      expect(command.calls, 1);
    });

    test('невыполнимая команда всё равно даёт кнопке название', () {
      final command = RecordingCommand(id: 'copy', executable: false, label: 'Copy');
      final registry = CommandRegistry([command], [KeyBinding('F5', 'copy')]);
      build(registry);

      // Кнопка показывает «Copy» и остаётся приглушённой.
      expect(registry.commandFor(KeyCombination.parse('F5')), command);
      expect(registry.isExecutable(command), isFalse);
      expect(registry.dispatch(KeyCombination.parse('F5')), isFalse);
      expect(command.calls, 0);
    });

    test('за клавишей стоит та команда, которая по ней и сработает', () {
      final blocked = RecordingCommand(id: 'blocked', executable: false);
      final ready = RecordingCommand(id: 'ready');
      final registry = CommandRegistry([blocked, ready], [KeyBinding('F5', 'blocked'), KeyBinding('F5', 'ready')]);
      build(registry);

      expect(registry.commandFor(KeyCombination.parse('F5')), ready);
      registry.dispatch(KeyCombination.parse('F5'));
      expect(ready.calls, 1);
      expect(blocked.calls, 0);
    });
  });

  group('привязками заведует реестр', () {
    test('привязку можно поставить и снять, не трогая команду', () {
      final command = RecordingCommand(id: 'custom');
      final registry = CommandRegistry([command]);
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F5')), isFalse);

      registry.bind(KeyBinding('F5', 'custom'));
      expect(registry.dispatch(KeyCombination.parse('F5')), isTrue);
      expect(command.calls, 1);

      registry.unbind('custom');
      expect(registry.dispatch(KeyCombination.parse('F5')), isFalse);
      expect(command.calls, 1);
    });

    test('клавишу можно переназначить на другую команду', () {
      final copy = RecordingCommand(id: 'copy', label: 'Copy');
      final move = RecordingCommand(id: 'move', label: 'Move');
      final registry = CommandRegistry([copy, move], [KeyBinding('F5', 'copy')]);
      build(registry);

      registry.unbind('copy');
      registry.bind(KeyBinding('F5', 'move'));

      // Ни одна из команд об этом не знает.
      expect(registry.commandFor(KeyCombination.parse('F5')), move);
      registry.dispatch(KeyCombination.parse('F5'));
      expect(move.calls, 1);
      expect(copy.calls, 0);
    });

    test('реестр знает, чем вызывается команда', () {
      final registry = defaultCommandRegistry();
      build(registry);

      final keys = registry.bindingsOf('panel.cursor.first').map((b) => b.keys.toString());
      expect(keys, ['Home', 'Left']);
    });

    test('привязка к неизвестной команде игнорируется', () {
      final registry = CommandRegistry([], [KeyBinding('F5', 'нет.такой.команды')]);
      build(registry);

      // Такое остаётся от старых настроек после переименования команды.
      expect(registry.commandFor(KeyCombination.parse('F5')), isNull);
      expect(registry.dispatch(KeyCombination.parse('F5')), isFalse);
    });

    test('каждая привязка ссылается на существующую команду', () {
      final ids = defaultCommands().map((command) => command.id).toSet();
      for (final binding in defaultKeyBindings()) {
        expect(ids, contains(binding.commandId), reason: 'привязка $binding указывает в пустоту');
      }
    });
  });

  group('команда не зависит от способа вызова', () {
    test('любую команду можно выполнить без клавиатуры', () async {
      final registry = defaultCommandRegistry();
      build(registry);
      await app.start();

      // Так команды будут вызываться из списка команд и из меню.
      expect(registry.run(registry.find('panel.cursor.down')!), isTrue);
      expect(app.left.cursorIndex, 1);

      expect(registry.run(registry.find('panel.cursor.last')!), isTrue);
      expect(app.left.cursorIndex, app.left.nodes.length - 1);

      expect(registry.run(registry.find('panel.cursor.first')!), isTrue);
      expect(app.left.cursorIndex, 0);

      expect(registry.run(registry.find('app.togglePanel')!), isTrue);
      expect(app.activePanel, app.right);
    });

    test('вызов клавишей и вызов из списка команд дают одно и то же', () async {
      final registry = defaultCommandRegistry();
      build(registry);
      await app.start();

      registry.dispatch(KeyCombination.parse('Down'));
      final byKey = app.left.cursorIndex;

      app.left.setCursorToFirst();
      registry.run(registry.find('panel.cursor.down')!);

      expect(app.left.cursorIndex, byKey);
    });

    test('противоположные действия — разные команды', () {
      final registry = defaultCommandRegistry();
      build(registry);

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
        expect(registry.find(id), isNotNull, reason: 'нет команды $id');
      }
    });

    test('у каждой команды есть название для списка команд', () {
      for (final command in defaultCommands()) {
        expect(command.label, isNotEmpty, reason: 'у ${command.id} нет названия');
      }
    });
  });

  group('набор команд по умолчанию', () {
    test('файловые операции закреплены за клавишами, но пока не выполняются', () {
      final registry = defaultCommandRegistry();
      build(registry);

      final copy = registry.commandFor(KeyCombination.parse('F5'));
      expect(copy?.id, 'file.copy');
      expect(registry.isExecutable(copy!), isFalse);
    });

    test('F9 и F10 пока ни за кем не закреплены', () {
      final registry = defaultCommandRegistry();
      build(registry);

      expect(registry.commandFor(KeyCombination.parse('F9')), isNull);
      expect(registry.commandFor(KeyCombination.parse('F10')), isNull);
    });

    test('у команд нет одинаковых идентификаторов', () {
      final ids = defaultCommands().map((command) => command.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('Esc во время чтения отменяет операцию, а не снимает пометку', () async {
      final registry = defaultCommandRegistry();
      build(registry);
      await app.start();

      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();

      // Пока панель занята, Esc должен доставаться команде отмены.
      final opening = app.left.openPath('/home/docs');
      expect(app.left.busy, isTrue);
      registry.dispatch(KeyCombination.parse('Esc'));
      await opening;

      expect(app.left.directory?.pathString, '/home');
      expect(app.left.selection.names, {'notes.txt'});

      // Панель свободна — теперь Esc снимает пометку.
      registry.dispatch(KeyCombination.parse('Esc'));
      expect(app.left.selection.isEmpty, isTrue);
    });

    test('Cmd-O открывает объект системой, не входя в каталог', () async {
      final opened = <String>[];
      final registry = CommandRegistry(
        [OpenWithSystemCommand(opener: (path) async => opened.add(path))],
        [KeyBinding('Cmd-O', 'panel.openWithSystem')],
      );
      build(registry);
      await app.start();

      app.left.setCursorToName('docs');
      registry.dispatch(KeyCombination.parse('Cmd-O'));
      await Future<void>.delayed(Duration.zero);

      expect(opened, ['/home/docs']);
      expect(app.left.directory?.pathString, '/home');
    });

    test('Enter на файле отдаёт его системе', () async {
      final opened = <String>[];
      final registry = CommandRegistry(
        [OpenNodeCommand(opener: (path) async => opened.add(path))],
        [KeyBinding('Enter', 'panel.open')],
      );
      build(registry);
      await app.start();

      app.left.setCursorToName('notes.txt');
      registry.dispatch(KeyCombination.parse('Enter'));
      await Future<void>.delayed(Duration.zero);

      expect(opened, ['/home/notes.txt']);
    });
  });
}
