import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/modules/app_shell.dart';
import 'package:flex_commander/core/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Модуль, который объявляет всё сразу: службу, команду, клавишу, тему и
/// стартовую команду. По нему и проверяется, что сборка ничего не теряет.
class ProbeModule implements FcFrontendModule, FcModuleLifecycle {
  ProbeModule({this.startupLog});

  final List<String>? startupLog;
  bool disposed = false;

  @override
  String get id => 'test.probe';

  @override
  String get title => 'Probe';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.service<ProbeService>((services) => const ProbeService('собрана'));
    registry.command((context) => ProbeCommand(context));
    registry.binding(KeyBinding('F9', 'test.probe'));
    registry.theme(
      const FcThemeSpec(
        id: 'probe',
        title: 'Probe theme',
        colors: DefaultColors(),
        metrics: DefaultMetrics(),
        icons: DefaultIcons(),
        fonts: DefaultFonts(),
      ),
    );
    if (startupLog case final log?) {
      registry.startup((context) => StartupCommand(log, context));
    }
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class ProbeService {
  const ProbeService(this.value);

  final String value;
}

/// Команда модуля: всё, что ей нужно, она берёт из окружения.
class ProbeCommand extends AppCommand {
  ProbeCommand(this.env);

  final FcContext env;

  @override
  String get id => 'test.probe';

  @override
  String get label => 'Probe';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {}

  String get serviceValue => env.resolve<ProbeService>().value;

  Panel get activePanel => env.app.activePanel;
}

class StartupCommand extends AppCommand {
  StartupCommand(this.log, this.env);

  final List<String> log;
  final FcContext env;

  @override
  String get id => 'test.startup';

  @override
  String get label => 'Startup';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    // Приложение к этому моменту собрано: стартовая команда работает с ним, а
    // не с полуготовым контейнером.
    //
    // Спрашивается снимок источника, а не путь: каталоги открывает **ядро** на
    // запуске, а стартовые команды идут раньше — панель в этот миг ещё пуста, и
    // так и должно быть (`spec/client-server.md`, §9).
    log.add(env.app.activePanel.source.rootPath);
  }
}

/// Модуль, который падает при запуске.
class BrokenStartupModule implements FcFrontendModule {
  const BrokenStartupModule();

  @override
  String get id => 'test.broken';

  @override
  String get title => 'Broken';

  @override
  void installFrontend(FrontendRegistry registry) => registry.startup((context) => _BrokenCommand());
}

class _BrokenCommand extends AppCommand {
  @override
  String get id => 'test.broken';

  @override
  String get label => 'Broken';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async => throw StateError('модуль сломался');
}

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late SettingsStore store;
  late FakeWindowService window;

  setUp(() async {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1)]);
    temp = await Directory.systemTemp.createTemp('flex_commander_bootstrap');
    store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home');
    window = FakeWindowService();
  });

  tearDown(() => temp.delete(recursive: true));

  /// Приложение целиком, но на подставных службах.
  Future<AppRuntime> build([List<FcModule> extra = const []]) async {
    // Платформенное подставное: настоящий модуль локальной ФС открывал бы
    // файлы системой прямо из теста.
    final all = <FcModule>[const TestPlatformBackend(), const TestPlatformFrontend(), ...featureModules(), ...extra];
    final runtime = await initModules(
      all.whereType<FcBackendModule>().toList(),
      all.whereType<FcFrontendModule>().toList(),
      overrides: AppOverrides(provider: provider, store: store, window: window),
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  group('сборка', () {
    test('приложение собирается из модулей', () async {
      final runtime = await build();

      expect(runtime.app.left, isNot(same(runtime.app.right)));
      expect(runtime.app.leftSession.provider, same(provider));
      expect(runtime.app.window, same(window));
      expect(runtime.commands.installed, isNotEmpty);
    });

    test('без оформления сборка не начинается', () async {
      // Красить нечем: значений оформления в API нет вовсе, их приносит модуль.
      await expectLater(
        initModules(
          [const AppShell(), const TestPlatformBackend()],
          [const AppShell(), const TestPlatformFrontend()],
          overrides: AppOverrides(provider: provider, store: store, window: window),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('без корневого источника сборка не начинается', () async {
      // Ошибка внятная и сразу: приложение без дерева бессмысленно.
      await expectLater(
        initModules([const AppShell(), const TestPlatformBackend()], [const AppShell(), const TestPlatformFrontend()]),
        throwsA(isA<StateError>()),
      );
    });

    test('настройки читаются до создания приложения', () async {
      await store.save(
        AppSettings.defaults('/home')
          ..splitRatio = 0.3
          ..activePanel = 1,
      );

      final runtime = await build();

      expect(runtime.app.splitRatio, 0.3);
      expect(runtime.app.activePanel, same(runtime.app.right));
    });

    test('приложение доступно и как интерфейс, и как реализация', () async {
      final runtime = await build();

      expect(runtime.app, isA<Application>());
      expect(runtime.app.left, isA<Panel>());
      expect(runtime.app.left.marked, isA<Set<String>>());
    });
  });

  group('объявления модуля', () {
    test('команда, клавиша, служба и тема доходят до приложения', () async {
      final runtime = await build([ProbeModule()]);

      final command = runtime.commands.find('test.probe');
      expect(command, isNotNull);
      expect(runtime.commands.bindingsOf('test.probe'), hasLength(1));
      expect(runtime.theme.available.map((theme) => theme.id), contains('probe'));

      // Команда получила окружение: служба своего же модуля и приложение.
      expect((command! as ProbeCommand).serviceValue, 'собрана');
      expect((command as ProbeCommand).activePanel, same(runtime.app.activePanel));
    });

    test('стартовая команда выполняется после сборки', () async {
      final log = <String>[];
      await build([ProbeModule(startupLog: log)]);

      expect(log, ['/'], reason: 'приложение и его источник уже на руках');
    });

    test('упавшая стартовая команда не роняет запуск', () async {
      final runtime = await build([const BrokenStartupModule()]);

      // Модуль темы не смог восстановить оформление — приложение всё равно
      // должно открыться.
      expect(runtime.app.left, isNotNull);
    });

    test('второй корневой источник — ошибка сборки, а не тихая замена', () async {
      await expectLater(
        initModules([const AppShell(), const _SecondRootModule(), const _OtherRootModule()], [const AppShell()]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('закрытие', () {
    test('модули закрываются вместе с приложением', () async {
      final probe = ProbeModule();
      final runtime = await build([probe]);

      await runtime.dispose();

      expect(probe.disposed, isTrue);
    });
  });

  group('повторная установка', () {
    test('модуль с тем же именем устанавливается один раз', () async {
      // Список модулей складывается из нескольких мест, и один и тот же модуль
      // легко указать дважды: повторная установка удвоила бы его привязки.
      final runtime = await build([ProbeModule(), ProbeModule()]);

      expect(runtime.modules.where((module) => module.id == 'test.probe'), hasLength(1));
      expect(runtime.commands.bindingsOf('test.probe'), hasLength(1));
    });
  });
}

class _SecondRootModule implements FcBackendModule {
  const _SecondRootModule();

  @override
  String get id => 'test.root';

  @override
  String get title => 'Root';

  @override
  void installBackend(BackendRegistry registry) => registry.rootProvider((services) => InMemoryTreeProvider([]));
}

/// Второй корень объявляет **другой** модуль: одинаковые устанавливаются один
/// раз, и спор о корне при этом не начинался бы вовсе.
class _OtherRootModule implements FcBackendModule {
  const _OtherRootModule();

  @override
  String get id => 'test.root.other';

  @override
  String get title => 'Another root';

  @override
  void installBackend(BackendRegistry registry) => registry.rootProvider((services) => InMemoryTreeProvider([]));
}
