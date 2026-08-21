import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flex_commander/modules/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модуль с архивом: `.arc` открывается как дерево.
class _ArchiveModule implements FcModule {
  _ArchiveModule(this.opened);

  /// Всё, что смонтировали за прогон: по ним видно, что закрылось, а что нет.
  final List<InMemoryArchiveProvider> opened;

  @override
  String get id => 'test.arc';

  @override
  String get title => 'Archives';

  @override
  void install(FcRegistry registry) {
    registry.provider(
      'arc',
      (host) => TaskOperation<TreeProvider>((op) async {
        final provider = InMemoryArchiveProvider([
          FakeEntry.directory('/inner'),
          FakeEntry.file('/inner/doc.txt', content: [1, 2, 3]),
          FakeEntry.file('/readme.md', content: [4]),
        ], host);
        opened.add(provider);
        return provider;
      }),
      extensions: {'arc'},
    );
  }
}

/// После работы приложения не остаётся ничего открытого.
///
/// Проверка доктринальная: у неё нет своего сценария сверх обычной работы —
/// походили по архиву, набрали путь внутрь него, ушли. Смысл в том, что
/// **таблица смонтированного пуста**, чем бы прогон ни кончился. Иначе где-то
/// остался открытый файл, временная копия или живое соединение.
void main() {
  late List<InMemoryArchiveProvider> opened;

  /// Приложение собирается напрямую, а не через `testApp`: тот закрывает его
  /// сам в конце теста, а здесь закрытие — часть проверки.
  Future<AppRuntime> app() async {
    opened = [];
    final disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/archive.arc', content: [0]),
      FakeEntry.file('/home/notes.txt', size: 3),
    ])..home = '/home';

    final runtime = await initModules(
      [
        const AppShell(),
        const TestPlatform(),
        const DefaultTheme(),
        ...featureModules(),
        _ArchiveModule(opened),
      ],
      overrides: AppOverrides(
        provider: disk,
        store: InMemorySettingsStore(
          settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
          homePath: '/home',
        ),
        window: FakeWindowService(),
        saveDelay: const Duration(milliseconds: 5),
      ),
    );
    await runtime.app.start();
    return runtime;
  }

  /// Закрытие провайдера асинхронное, и запись живёт до его конца: без этого
  /// проверка успевает увидеть таблицу с записью на нуле арендаторов.
  Future<void> settle() => pumpEventQueue();

  test('походили по архиву и ушли — не осталось ничего', () async {
    final runtime = await app();
    final left = runtime.app.left;

    left.setCursorToName('archive.arc');
    await left.enterCurrent();
    expect(opened, hasLength(1));

    left.setCursorToName('inner');
    await left.enterCurrent();
    await left.goUp();
    await left.goUp();

    expect(opened.single.closed, isTrue);
    await settle();
    expect(runtime.providers?.mounted, isEmpty);

    await runtime.dispose();
  });

  test('обе панели в одном архиве — один экземпляр на двоих', () async {
    final runtime = await app();

    for (final panel in [runtime.app.left, runtime.app.right]) {
      panel.setCursorToName('archive.arc');
      await panel.enterCurrent();
    }

    // Два экземпляра поверх одного файла разошлись бы состоянием.
    expect(opened, hasLength(1));
    expect(runtime.app.right.provider, same(runtime.app.left.provider));
    expect(runtime.providers?.mounted.single.tenants, 2);

    await runtime.dispose();
    await settle();
    expect(opened.single.closed, isTrue);
    expect(runtime.providers?.mounted, isEmpty);
  });

  test('выход закрывает то, что осталось открытым', () async {
    final runtime = await app();

    // Панель уходит вместе с приложением, не выходя из архива, — так и бывает
    // на самом деле: закрывают окно, стоя где стояли.
    runtime.app.left.setCursorToName('archive.arc');
    await runtime.app.left.enterCurrent();
    expect(opened.single.closed, isFalse);

    await runtime.dispose();
    await settle();

    expect(opened.single.closed, isTrue, reason: 'открытый файл не должен пережить процесс');
    expect(runtime.providers?.mounted, isEmpty);
  });
}
