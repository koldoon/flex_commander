import 'dart:io';

import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/app_command.dart';
import 'package:flex_commander/state/commands/command_registry.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/commands/key_combination.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Журнал вызовов.
///
/// Экземпляр команды создаётся на каждый запуск, поэтому считать вызовы
/// на самом экземпляре бессмысленно — они пишутся в общий журнал.
class CommandLog {
  final List<String> calls = [];
  final List<String> runIds = [];
  final Map<String, List<String>> targets = {};

  int callsOf(String id) => calls.where((call) => call == id).length;
}

/// Команда-заглушка, которая отмечается в журнале.
class RecordingCommand extends AppCommand {
  RecordingCommand({required this.id, required this.log, bool executable = true, this.label = 'Recording'})
    : _executable = executable;

  @override
  final String id;

  @override
  final String label;

  final CommandLog log;
  final bool _executable;

  @override
  bool isExecutable(CommandContext context) => _executable;

  @override
  Future<void> execute() async {
    log.calls.add(id);
    log.runIds.add(runId);
    log.targets[id] = context.targets.map((node) => node.name).toList();
  }
}

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;
  late CommandLog log;

  /// Не каждому тесту нужно приложение: чистые проверки набора команд
  /// обходятся без него, и завершение теста не должно на этом спотыкаться.
  var appBuilt = false;

  setUp(() async {
    log = CommandLog();
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

  CommandFactory recording(String id, {bool executable = true, String label = 'Recording'}) {
    return () => RecordingCommand(id: id, log: log, executable: executable, label: label);
  }

  group('разбор нажатия', () {
    test('выполняется первая подходящая команда', () {
      final registry = CommandRegistry(
        [recording('first'), recording('second')],
        [KeyBinding('F5', 'first'), KeyBinding('F5', 'second')],
      );
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F5')), isTrue);
      expect(log.callsOf('first'), 1);
      expect(log.callsOf('second'), 0);
    });

    test('невыполнимая команда пропускается', () {
      final registry = CommandRegistry(
        [recording('blocked', executable: false), recording('fallback')],
        [KeyBinding('F5', 'blocked'), KeyBinding('F5', 'fallback')],
      );
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F5')), isTrue);
      expect(log.callsOf('blocked'), 0);
      expect(log.callsOf('fallback'), 1);
    });

    test('нажатие без команды остаётся необработанным', () {
      final registry = CommandRegistry([recording('a')], [KeyBinding('F5', 'a')]);
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F6')), isFalse);
    });

    test('несколько привязок вызывают команду одинаково', () {
      final registry = CommandRegistry([recording('multi')], [KeyBinding('F5', 'multi'), KeyBinding('Cmd-E', 'multi')]);
      build(registry);

      registry.dispatch(KeyCombination.parse('F5'));
      registry.dispatch(KeyCombination.parse('Cmd-E'));

      // Команда не знает, чем её вызвали: обе привязки дают один и тот же вызов.
      expect(log.callsOf('multi'), 2);
    });

    test('фильтр по имени выбирает специализированную команду', () async {
      final registry = CommandRegistry(
        [recording('open.app'), recording('open')],
        [KeyBinding('Enter', 'open.app', nameMatch: RegExp(r'\.app$')), KeyBinding('Enter', 'open')],
      );
      build(registry);
      await app.start();

      app.left.setCursorToName('notes.txt');
      registry.dispatch(KeyCombination.parse('Enter'));
      expect(log.callsOf('open.app'), 0);
      expect(log.callsOf('open'), 1);

      app.left.setCursorToName('setup.app');
      registry.dispatch(KeyCombination.parse('Enter'));
      expect(log.callsOf('open.app'), 1);
      expect(log.callsOf('open'), 1);
    });
  });

  group('экземпляр на запуск', () {
    test('каждый запуск получает свой идентификатор', () {
      final registry = CommandRegistry([recording('twice')], [KeyBinding('F5', 'twice')]);
      build(registry);

      registry.dispatch(KeyCombination.parse('F5'));
      registry.dispatch(KeyCombination.parse('F5'));

      // Состояние исполнения принадлежит запуску, а не команде вообще.
      expect(log.runIds, hasLength(2));
      expect(log.runIds.first, isNot(log.runIds.last));
      expect(log.runIds.first, startsWith('twice#'));
    });

    test('в списке команд остаётся один экземпляр на команду', () {
      final registry = CommandRegistry([recording('one'), recording('two')]);
      build(registry);

      expect(registry.installed.map((command) => command.id), ['one', 'two']);
      expect(registry.find('one'), same(registry.find('one')));
    });
  });

  group('условия команды', () {
    test('без пометки целью становится объект под курсором', () async {
      final registry = CommandRegistry([recording('targets')], [KeyBinding('F5', 'targets')]);
      build(registry);
      await app.start();

      app.left.setCursorToName('notes.txt');
      registry.dispatch(KeyCombination.parse('F5'));

      expect(log.targets['targets'], ['notes.txt']);
    });

    test('с пометкой целями становятся помеченные объекты', () async {
      final registry = CommandRegistry([recording('targets')], [KeyBinding('F5', 'targets')]);
      build(registry);
      await app.start();

      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();
      app.left.toggleCurrentMark();
      registry.dispatch(KeyCombination.parse('F5'));

      expect(log.targets['targets'], ['notes.txt', 'report.xlsx']);
    });

    test('контекст берёт активную панель, а пассивная — приёмник', () async {
      final registry = CommandRegistry([recording('ctx')]);
      build(registry);
      await app.start();

      app.toggleActivePanel();
      final context = registry.contextFor(registry.find('ctx')!);

      expect(context.panel, app.right);
      expect(context.target, app.left);
    });
  });

  group('привязками заведует реестр', () {
    test('привязку можно поставить и снять, не трогая команду', () {
      final registry = CommandRegistry([recording('custom')]);
      build(registry);

      expect(registry.dispatch(KeyCombination.parse('F5')), isFalse);

      registry.bind(KeyBinding('F5', 'custom'));
      expect(registry.dispatch(KeyCombination.parse('F5')), isTrue);
      expect(log.callsOf('custom'), 1);

      registry.unbind('custom');
      expect(registry.dispatch(KeyCombination.parse('F5')), isFalse);
      expect(log.callsOf('custom'), 1);
    });

    test('клавишу можно переназначить на другую команду', () {
      final registry = CommandRegistry(
        [recording('copy', label: 'Copy'), recording('move', label: 'Move')],
        [KeyBinding('F5', 'copy')],
      );
      build(registry);

      registry.unbind('copy');
      registry.bind(KeyBinding('F5', 'move'));

      // Ни одна из команд об этом не знает.
      expect(registry.commandFor(KeyCombination.parse('F5'))?.id, 'move');
      registry.dispatch(KeyCombination.parse('F5'));
      expect(log.callsOf('move'), 1);
      expect(log.callsOf('copy'), 0);
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
      final registry = defaultCommandRegistry();
      build(registry);
      final ids = registry.installed.map((command) => command.id).toSet();

      for (final binding in defaultKeyBindings()) {
        expect(ids, contains(binding.commandId), reason: 'привязка $binding указывает в пустоту');
      }
    });
  });

  group('нижняя панель — та же клавиатура', () {
    test('кнопка находит команду по её привязке к клавише', () {
      final registry = CommandRegistry([recording('copy', label: 'Copy')], [KeyBinding('F5', 'copy')]);
      build(registry);

      // Команда не объявляет, где её показывать: панель спрашивает,
      // что закреплено за F5.
      expect(registry.commandFor(KeyCombination.parse('F5'))?.id, 'copy');
      expect(registry.commandFor(KeyCombination.parse('F6')), isNull);
    });

    test('нажатие кнопки равносильно нажатию клавиши', () {
      final registry = CommandRegistry([recording('copy')], [KeyBinding('F5', 'copy')]);
      build(registry);

      registry.dispatch(KeyCombination.parse('F5'));
      expect(log.callsOf('copy'), 1);
    });

    test('невыполнимая команда всё равно даёт кнопке название', () {
      final registry = CommandRegistry(
        [recording('copy', executable: false, label: 'Copy')],
        [KeyBinding('F5', 'copy')],
      );
      build(registry);

      final command = registry.commandFor(KeyCombination.parse('F5'))!;
      expect(command.label, 'Copy');
      expect(registry.isExecutable(command), isFalse);
      expect(registry.dispatch(KeyCombination.parse('F5')), isFalse);
      expect(log.calls, isEmpty);
    });

    test('за клавишей стоит та команда, которая по ней и сработает', () {
      final registry = CommandRegistry(
        [recording('blocked', executable: false), recording('ready')],
        [KeyBinding('F5', 'blocked'), KeyBinding('F5', 'ready')],
      );
      build(registry);

      expect(registry.commandFor(KeyCombination.parse('F5'))?.id, 'ready');
      registry.dispatch(KeyCombination.parse('F5'));
      expect(log.callsOf('ready'), 1);
      expect(log.callsOf('blocked'), 0);
    });
  });

  group('команда не зависит от способа вызова', () {
    test('любую команду можно выполнить без клавиатуры', () async {
      final registry = defaultCommandRegistry();
      build(registry);
      await app.start();

      // Так команды будут вызываться из списка команд и из меню.
      expect(registry.run('panel.cursor.down'), isTrue);
      expect(app.left.cursorIndex, 1);

      expect(registry.run('panel.cursor.last'), isTrue);
      expect(app.left.cursorIndex, app.left.nodes.length - 1);

      expect(registry.run('panel.cursor.first'), isTrue);
      expect(app.left.cursorIndex, 0);

      expect(registry.run('app.togglePanel'), isTrue);
      expect(app.activePanel, app.right);
    });

    test('вызов клавишей и вызов из списка команд дают одно и то же', () async {
      final registry = defaultCommandRegistry();
      build(registry);
      await app.start();

      registry.dispatch(KeyCombination.parse('Down'));
      final byKey = app.left.cursorIndex;

      app.left.setCursorToFirst();
      registry.run('panel.cursor.down');

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
      final registry = defaultCommandRegistry();
      build(registry);

      for (final command in registry.installed) {
        expect(command.label, isNotEmpty, reason: 'у ${command.id} нет названия');
      }
    });
  });

  group('набор команд по умолчанию', () {
    test('файловые операции закреплены за клавишами', () {
      final registry = defaultCommandRegistry();
      build(registry);

      expect(registry.commandFor(KeyCombination.parse('F5'))?.id, 'file.copy');
      expect(registry.commandFor(KeyCombination.parse('F7'))?.id, 'file.mkdir');
      expect(registry.commandFor(KeyCombination.parse('F8'))?.id, 'file.remove');
    });

    test('удаление умеет сообщать о ходе работы наружу', () {
      final registry = defaultCommandRegistry();
      build(registry);

      // Задел на фоновое выполнение: ядро сможет спрятать окно команды,
      // а прогресс показывать рядом с другими операциями.
      expect(registry.find('file.remove'), isA<AsyncCommand>());
      expect(registry.find('file.removePermanently'), isA<AsyncCommand>());
    });

    test('F9 и F10 пока ни за кем не закреплены', () {
      final registry = defaultCommandRegistry();
      build(registry);

      expect(registry.commandFor(KeyCombination.parse('F9')), isNull);
      expect(registry.commandFor(KeyCombination.parse('F10')), isNull);
    });

    test('у команд нет одинаковых идентификаторов', () {
      final registry = defaultCommandRegistry();
      build(registry);
      final ids = registry.installed.map((command) => command.id).toList();

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
  });
}
