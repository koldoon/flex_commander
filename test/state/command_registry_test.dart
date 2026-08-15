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
  RecordingCommand({
    required this.id,
    required List<KeyBinding> bindings,
    bool executable = true,
    this.label = 'Recording',
    this.functionKey,
  }) : _bindings = bindings,
       _executable = executable;

  @override
  final String id;

  @override
  final String label;

  @override
  final FunctionKeySlot? functionKey;

  final List<KeyBinding> _bindings;
  final bool _executable;

  int calls = 0;
  List<String> lastTargets = const [];

  @override
  List<KeyBinding> get bindings => _bindings;

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
    app.dispose();
    await temp.delete(recursive: true);
  });

  AppController build(CommandRegistry registry) {
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
      final first = RecordingCommand(id: 'first', bindings: [KeyBinding('F5')]);
      final second = RecordingCommand(id: 'second', bindings: [KeyBinding('F5')]);
      final registry = CommandRegistry([first, second]);
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F5')), isTrue);
      expect(first.calls, 1);
      expect(second.calls, 0);
    });

    test('невыполнимая команда пропускается', () async {
      final blocked = RecordingCommand(id: 'blocked', bindings: [KeyBinding('F5')], executable: false);
      final fallback = RecordingCommand(id: 'fallback', bindings: [KeyBinding('F5')]);
      final registry = CommandRegistry([blocked, fallback]);
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F5')), isTrue);
      expect(blocked.calls, 0);
      expect(fallback.calls, 1);
    });

    test('нажатие без команды остаётся необработанным', () {
      final registry = CommandRegistry([
        RecordingCommand(id: 'a', bindings: [KeyBinding('F5')]),
      ]);
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F6')), isFalse);
    });

    test('несколько привязок вызывают команду одинаково', () {
      final command = RecordingCommand(id: 'multi', bindings: [KeyBinding('F5'), KeyBinding('Cmd-E')]);
      final registry = CommandRegistry([command]);
      build(registry);

      registry.dispatch(KeyCombination.parse('F5'));
      registry.dispatch(KeyCombination.parse('Cmd-E'));

      // Команда не знает, чем её вызвали: обе привязки дают один и тот же вызов.
      expect(command.calls, 2);
    });

    test('фильтр по имени выбирает специализированную команду', () async {
      final apps = RecordingCommand(id: 'open.app', bindings: [KeyBinding('Enter', nameMatch: RegExp(r'\.app$'))]);
      final common = RecordingCommand(id: 'open', bindings: [KeyBinding('Enter')]);
      final registry = CommandRegistry([apps, common]);
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
      final command = RecordingCommand(id: 'targets', bindings: [KeyBinding('F5')]);
      build(CommandRegistry([command]));
      await app.start();

      app.left.setCursorToName('notes.txt');
      app.commands.dispatch(KeyCombination.parse('F5'));

      expect(command.lastTargets, ['notes.txt']);
    });

    test('с пометкой целями становятся помеченные объекты', () async {
      final command = RecordingCommand(id: 'targets', bindings: [KeyBinding('F5')]);
      build(CommandRegistry([command]));
      await app.start();

      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();
      app.left.toggleCurrentMark();
      app.commands.dispatch(KeyCombination.parse('F5'));

      expect(command.lastTargets, ['notes.txt', 'report.xlsx']);
    });

    test('контекст берёт активную панель, а пассивная — приёмник', () async {
      final command = RecordingCommand(id: 'ctx', bindings: [KeyBinding('F5')]);
      final registry = CommandRegistry([command]);
      build(registry);
      await app.start();

      app.toggleActivePanel();
      final context = registry.contextFor(command);

      expect(context.panel, app.right);
      expect(context.target, app.left);
    });
  });

  group('нижняя панель', () {
    test('слот занимает команда, которая его объявила', () {
      final copy = RecordingCommand(id: 'copy', bindings: [], label: 'Copy', functionKey: FunctionKeySlot.f5);
      final registry = CommandRegistry([copy]);
      build(registry);

      expect(registry.commandForSlot(FunctionKeySlot.f5), copy);
      expect(registry.commandForSlot(FunctionKeySlot.f6), isNull);
    });

    test('кнопка выполняет ту же команду, что и клавиша', () {
      final command = RecordingCommand(id: 'copy', bindings: [KeyBinding('F5')], functionKey: FunctionKeySlot.f5);
      final registry = CommandRegistry([command]);
      build(registry);

      expect(registry.run(command), isTrue);
      expect(command.calls, 1);
    });

    test('невыполнимая команда кнопкой не запускается', () {
      final command = RecordingCommand(id: 'copy', bindings: [], executable: false, functionKey: FunctionKeySlot.f5);
      final registry = CommandRegistry([command]);
      build(registry);

      expect(registry.isExecutable(command), isFalse);
      expect(registry.run(command), isFalse);
      expect(command.calls, 0);
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
      build(defaultCommandRegistry());
      for (final command in defaultCommands()) {
        expect(command.label, isNotEmpty, reason: 'у ${command.id} нет названия');
      }
    });
  });

  group('набор команд по умолчанию', () {
    test('файловые операции занимают слоты, но пока не выполняются', () {
      final registry = defaultCommandRegistry();
      build(registry);

      final copy = registry.commandForSlot(FunctionKeySlot.f5);
      expect(copy?.id, 'file.copy');
      expect(registry.isExecutable(copy!), isFalse);
    });

    test('слоты F9 и F10 пока свободны', () {
      final registry = defaultCommandRegistry();
      build(registry);

      expect(registry.commandForSlot(FunctionKeySlot.f9), isNull);
      expect(registry.commandForSlot(FunctionKeySlot.f10), isNull);
    });

    test('у команд нет одинаковых идентификаторов', () {
      build(defaultCommandRegistry());
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
      final registry = CommandRegistry([OpenWithSystemCommand(opener: (path) async => opened.add(path))]);
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
      final registry = CommandRegistry([OpenNodeCommand(opener: (path) async => opened.add(path))]);
      build(registry);
      await app.start();

      app.left.setCursorToName('notes.txt');
      registry.dispatch(KeyCombination.parse('Enter'));
      await Future<void>.delayed(Duration.zero);

      expect(opened, ['/home/notes.txt']);
    });
  });
}
