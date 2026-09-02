import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Журнал вызовов.
///
/// Команда — один экземпляр на всё приложение, и своего состояния прогона у неё
/// нет: что и с чем вызывали, видно только снаружи.
class CommandLog {
  final List<String> calls = [];
  final Map<String, List<String>> targets = {};
  final Map<String, Map<String, Object?>> parameters = {};

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
  Future<void> execute(CommandContext context) async {
    log.calls.add(id);
    log.targets[id] = context.targets.map((node) => node.name).toList();
    log.parameters[id] = context.invocation.parameters;
  }
}

/// Команда, которая падает: раньше её ошибка пропадала бесследно.
class FailingCommand extends AppCommand {
  FailingCommand({required this.id, required this.failure});

  @override
  final String id;

  @override
  String get label => 'Failing';

  final Object failure;

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async => throw failure;
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
      left: testPanel(provider: provider, settings: settings.left),
      right: testPanel(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      commands: registry,
      saveDelay: const Duration(milliseconds: 5),
    );
  }

  AppCommandFactory recording(String id, {bool executable = true, String label = 'Recording'}) {
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

  group('команда — прототип', () {
    test('оба нажатия идут через один и тот же экземпляр', () {
      final registry = CommandRegistry([recording('twice')], [KeyBinding('F5', 'twice')]);
      build(registry);

      registry.dispatch(KeyCombination.parse('F5'));
      registry.dispatch(KeyCombination.parse('F5'));

      // Второго экземпляра команде не нужно: состояние прогона живёт в окне
      // или в работе, а не в ней самой.
      expect(log.callsOf('twice'), 2);
      expect(registry.installed.where((command) => command.id == 'twice'), hasLength(1));
    });

    test('значения принадлежат вызову, а не команде', () {
      final registry = CommandRegistry([recording('args')]);
      build(registry);

      registry.run('args', const CommandInvocation(parameters: {'name': 'первый'}));
      expect(log.parameters['args'], {'name': 'первый'});

      // Второй запуск не видит значений первого — их негде было запомнить.
      registry.run('args');
      expect(log.parameters['args'], isEmpty);
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

    group('любой печатный символ', () {
      test('набранный символ приходит команде параметром', () {
        final registry = CommandRegistry([recording('jump')], [const KeyBinding.anyCharacter('jump')]);
        build(registry);

        expect(registry.dispatch(const KeyCombination('D')), isTrue);
        expect(log.parameters['jump'], {'character': 'D'});
      });

      test('сочетание с модификатором вводом символа не считается', () {
        final registry = CommandRegistry([recording('jump')], [const KeyBinding.anyCharacter('jump')]);
        build(registry);

        expect(registry.dispatch(KeyCombination.parse('Cmd-D')), isFalse);
        expect(log.callsOf('jump'), 0);
      });

      test('заглавная буква — тот же символ', () {
        final registry = CommandRegistry([recording('jump')], [const KeyBinding.anyCharacter('jump')]);
        build(registry);

        expect(registry.dispatch(const KeyCombination('D', shift: true)), isTrue);
      });

      test('именованные клавиши не перехватываются', () {
        final registry = CommandRegistry([recording('jump')], [const KeyBinding.anyCharacter('jump')]);
        build(registry);

        for (final key in ['Space', 'Enter', 'Esc', 'F5', 'Up']) {
          expect(registry.dispatch(KeyCombination.parse(key)), isFalse, reason: key);
        }
      });

      test('привязка к конкретной клавише важнее', () {
        final registry = CommandRegistry(
          [recording('specific'), recording('jump')],
          [KeyBinding('D', 'specific'), const KeyBinding.anyCharacter('jump')],
        );
        build(registry);

        registry.dispatch(const KeyCombination('D'));

        expect(log.callsOf('specific'), 1);
        expect(log.callsOf('jump'), 0);
      });

      // Переехало в dependency/navigation: команды и клавиши навигации живут
      // там же, где и сам модуль.
    });

    // Переехало в dependency/navigation: команды и клавиши навигации живут
    // там же, где и сам модуль.

    // Переехало в dependency/navigation: команды и клавиши навигации живут
    // там же, где и сам модуль.

    test('привязка передаёт команде значения', () {
      final registry = CommandRegistry(
        [recording('sort')],
        [
          KeyBinding('F5', 'sort', parameters: {'column': 'name'}),
        ],
      );
      build(registry);

      registry.dispatch(KeyCombination.parse('F5'));

      // Одна команда на разных клавишах с разными значениями.
      expect(log.parameters['sort'], {'column': 'name'});
    });

    test('привязка к неизвестной команде игнорируется', () {
      final registry = CommandRegistry([], [KeyBinding('F5', 'нет.такой.команды')]);
      build(registry);

      // Такое остаётся от старых настроек после переименования команды.
      expect(registry.commandFor(KeyCombination.parse('F5')), isNull);
      expect(registry.dispatch(KeyCombination.parse('F5')), isFalse);
    });

    // Проверка «каждая привязка указывает на установленную команду» переехала
    // в test/app/bindings_test.dart: набор привязок теперь собирается из
    // модулей, и проверять его нужно на собранном приложении.
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
    // Переехало в dependency/navigation: команды и клавиши навигации живут
    // там же, где и сам модуль.

    // Переехало в dependency/navigation: команды и клавиши навигации живут
    // там же, где и сам модуль.

    // Переехало в dependency/navigation: команды и клавиши навигации живут
    // там же, где и сам модуль.

    // Про собранный набор команд — в test/app/bindings_test.dart: набор
    // складывается из модулей, и проверять его нужно на собранном приложении.
  });

  group('исход запуска', () {
    test('ошибка команды без окна доходит до обработчика', () async {
      final failures = <Object>[];
      final registry = CommandRegistry(
        [() => FailingCommand(id: 'broken', failure: 'нет доступа')],
        [KeyBinding('F5', 'broken')],
        (error, command) => failures.add(error),
      );
      build(registry);

      expect(registry.dispatch(KeyCombination('F5')), isTrue);
      // Запуск не ждут — нажатие клавиши не может стоять до конца работы, —
      // поэтому исход разбирается следующим шагом цикла событий.
      await Future<void>.delayed(Duration.zero);

      expect(failures, ['нет доступа']);
    });

    test('успешный запуск обработчика ошибок не трогает', () async {
      final failures = <Object>[];
      final registry = CommandRegistry(
        [recording('fine')],
        [KeyBinding('F5', 'fine')],
        (error, _) => failures.add(error),
      );
      build(registry);

      registry.dispatch(KeyCombination('F5'));
      await Future<void>.delayed(Duration.zero);

      expect(log.callsOf('fine'), 1);
      expect(failures, isEmpty);
    });
  });
}
