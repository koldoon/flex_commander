import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_modules.dart';

/// Панель идёт за оболочкой — но только когда та **ушла сама**.
///
/// Оболочка отмечается на каждом приглашении, в том числе на первом, которое
/// печатает при запуске. Первое — не переход: она говорит, где её запустили, а
/// запускали её не там, где стоит панель, и вообще не спрашивая. Пойти за ним
/// значит увести человека из каталога, в котором он был, — а грелую оболочку он
/// и вовсе не просил.
void main() {
  late FakePty pty;
  late AppRuntime runtime;

  setUp(() async {
    pty = FakePty();
    final provider = InMemoryTreeProvider(
      [FakeEntry.directory('/home'), FakeEntry.directory('/home/docs'), FakeEntry.directory('/work')],
      null,
      pty,
    )..home = '/home';

    runtime = await testApp(
      provider: provider,
      modules: modulesWithTerminal(),
      backend: [_LocalShell(pty)],
      settings: AppSettings(left: PanelSettings.defaults('/home/docs'), right: PanelSettings.defaults('/work')),
    );
    await runtime.app.start();
    // Оболочку греют при запуске: к этому мигу она уже запущена и получила
    // уговор о метках.
    await waitUntil(() => pty.started);
  });

  tearDown(() => runtime.dispose());

  /// Число этой сессии — из того, что ей самой и отправили.
  ///
  /// Метка с чужим числом не разбирается вовсе (`spec/single-shell-session.md`),
  /// поэтому проверка берёт настоящее: так же его увидит и настоящая оболочка.
  String nonce() => RegExp(r'777;fc;([^;]+);').firstMatch(pty.session.written)!.group(1)!;

  /// Оболочка отметилась: печатает приглашение, находясь вот здесь.
  Future<void> promptAt(String directory) async {
    pty.session.emit('\x1b]777;fc;${nonce()};p;0;$directory\x07');
    await pumpEventQueue();
  }

  test('первое приглашение панель не уводит', () async {
    expect(runtime.app.left.path, '/home/docs', reason: 'панель встала туда, где её оставили');

    // Оболочку грели при запуске, и начала она там, откуда запустили процесс.
    await promptAt('/home');

    expect(runtime.app.left.path, '/home/docs', reason: 'оболочка никуда не ходила — и панель не должна');
  });

  test('панель идёт за cd, набранным в терминале', () async {
    await promptAt('/home');

    // А вот это уже переход: между двумя приглашениями оболочка сменила
    // каталог, и сделал это человек.
    await promptAt('/work');

    expect(runtime.app.left.path, '/work');
  });

  test('приглашение в том же каталоге панель не трогает', () async {
    await promptAt('/home');
    await promptAt('/work');
    await runtime.app.left.openPath('/home/docs');

    // Команда кончилась там же, где начиналась: переходить некуда.
    await promptAt('/work');
    await promptAt('/work');

    expect(runtime.app.left.path, '/home/docs');
  });
}

/// Оболочка «этой машины» — подставная: настоящую прогон трогать не должен.
class _LocalShell implements FcBackendModule {
  const _LocalShell(this.pty);

  final FakePty pty;

  @override
  String get id => 'test.localShell';

  @override
  String get title => 'Local shell';

  @override
  void installBackend(BackendRegistry registry) {
    registry.service<ShellHost>((services) => _FakeHost(pty));
  }
}

class _FakeHost implements ShellHost {
  const _FakeHost(this.pty);

  final FakePty pty;

  @override
  String get shellLabel => 'localhost';

  @override
  String? get shellProgram => '/bin/zsh';

  @override
  String shellPath(String panelPath) => panelPath;

  @override
  Future<PtySession> run(String command, {String? directory, int columns = 80, int rows = 24}) async =>
      pty.start(executable: '/bin/zsh', arguments: ['-ic', command]);

  @override
  Future<PtySession> shell({String? directory, int columns = 80, int rows = 24}) async =>
      pty.start(executable: '/bin/zsh', arguments: ['-i']);
}
