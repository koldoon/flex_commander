import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';

import 'terminal_modules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оболочка своей машины заводится заранее.
///
/// Иначе первый `Ctrl-O` и первая команда ждут её запуска, чтения `.zshrc`,
/// уговора о метках и `clear` — и вся эта пауза приходится ровно на тот миг,
/// когда человек уже нажал клавишу.
void main() {
  late FakePty pty;

  Future<AppRuntime> start(List<FcModule> modules) async {
    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')], null, pty)..home = '/home',
      modules: modules,
    );
    await runtime.app.start();
    return runtime;
  }

  setUp(() => pty = FakePty());

  test('оболочка заводится при запуске, а не по первой просьбе', () async {
    await start([_LocalShell(pty), ...modulesWithTerminal()]);
    await pumpEventQueue();

    expect(pty.started, isTrue, reason: 'греется заранее');
    expect(pty.sessions, hasLength(1), reason: 'ровно одна — вторую заводить незачем');
  });

  test('греть нечем — приложение работает как прежде', () async {
    // Без модуля локальной ФС оболочки этой машины никто не объявляет. Это не
    // ошибка: приложение обязано собираться и работать без неё.
    final runtime = await start(modulesWithTerminal());
    await pumpEventQueue();

    expect(pty.started, isFalse);
    expect(runtime.app.view.contentAt(ViewportPosition.bottom), isNotNull, reason: 'строка на месте');
  });
}

/// Оболочка «этой машины» — подставная: настоящую прогон трогать не должен.
class _LocalShell implements FcModule {
  const _LocalShell(this.pty);

  final FakePty pty;

  @override
  String get id => 'test.localShell';

  @override
  String get title => 'Local shell';

  @override
  void install(FcRegistry registry) {
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
