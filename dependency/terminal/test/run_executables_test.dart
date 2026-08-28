import 'package:fc_api/fc_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_modules.dart';

/// `Enter` на файле с битом `+x` запускает его во внутреннем терминале
/// (`spec/run-executables.md`).
///
/// Главное здесь — не сам запуск, а **порядок разбора клавиши**: набранная
/// строка, потом исполняемый файл, потом вход в каталог. Никто из троих о
/// других не знает, и складывается порядок из объявления модулей и
/// выполнимости команд.
late AppRuntime runtime;
late FakePty pty;
late InMemoryTreeProvider provider;
late TerminalSettings settings;

Application get app => runtime.app;

CommandLineState get line => app.view.contentAt(ViewportPosition.bottom)! as CommandLineState;

bool press(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

void main() {
  setUp(() async {
    pty = FakePty();
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/build.sh', size: 10, executable: true),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file("/home/my script (2).sh", size: 10, executable: true),
    ])..home = '/home';
    runtime = await testApp(provider: provider, modules: modulesWithTerminal(pty));
    await runtime.app.start();
    settings = line.settings;
  });

  test('файл с +x запускается в каталоге панели', () async {
    app.left.setCursorToName('build.sh');
    expect(press('Enter'), isTrue);
    await pumpEventQueue();

    expect(pty.started, isTrue);
    expect(pty.session.arguments.last, '/home/build.sh');
    expect(pty.session.workingDirectory, '/home');
    // Каталог — параметр запуска, а не строка, отправленная оболочке.
    expect(pty.session.written, isEmpty);
  });

  test('имя с пробелом и скобками уходит целиком, а не кусками', () async {
    app.left.setCursorToName('my script (2).sh');
    press('Enter');
    await pumpEventQueue();

    expect(pty.session.arguments.last, "'/home/my script (2).sh'");
  });

  test('запуск помнится строкой: повторяют его тем же Cmd-Up', () async {
    app.left.setCursorToName('build.sh');
    press('Enter');
    await pumpEventQueue();

    expect(line.history, ['/home/build.sh']);
  });

  test('файл без +x уходит системе, как раньше', () async {
    app.left.setCursorToName('notes.txt');
    expect(press('Enter'), isTrue);
    await pumpEventQueue();

    expect(pty.started, isFalse);
  });

  test('каталог открывается каталогом, хотя +x у него есть', () async {
    app.left.setCursorToName('docs');
    press('Enter');
    await pumpEventQueue();

    expect(pty.started, isFalse);
    expect(app.left.directory?.pathString, '/home/docs');
  });

  test('без настоящего пути не запускается ничего: внутри архива запускать нечем', () async {
    provider.capabilities = archiveCapabilities;
    app.left.setCursorToName('build.sh');
    expect(press('Enter'), isTrue);
    await pumpEventQueue();

    expect(pty.started, isFalse);
  });

  test('выключенная настройка возвращает Enter системе', () async {
    settings.runExecutables = false;
    app.left.setCursorToName('build.sh');
    expect(press('Enter'), isTrue);
    await pumpEventQueue();

    expect(pty.started, isFalse);
  });

  test('набранная строка выигрывает у файла под курсором', () async {
    settings.typingGoesToLine = true;
    app.left.setCursorToName('build.sh');
    line.text.text = 'ls -la';
    press('Enter');
    await pumpEventQueue();

    expect(pty.session.arguments.last, 'ls -la');
  });

  group('показ — тот же, что у команды из строки', () {
    test('молча и успешно — экрана нет вовсе', () async {
      app.left.setCursorToName('build.sh');
      press('Enter');
      await pumpEventQueue();

      pty.session.exit(0);
      await pumpEventQueue();

      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);
    });

    test('сказала слово — экран остаётся', () async {
      app.left.setCursorToName('build.sh');
      press('Enter');
      await pumpEventQueue();

      pty.session.emit('done\r\n');
      await pumpEventQueue();
      pty.session.exit(0);
      await pumpEventQueue();

      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<CommandRunScreen>());
      expect((screen! as CommandRunScreen).command, '/home/build.sh');
    });
  });

  test('без модуля терминала Enter ведёт себя как раньше', () async {
    final plain = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/build.sh', size: 10, executable: true),
      ])..home = '/home',
      modules: [
        for (final module in modulesWithTerminal(FakePty()))
          if (module.id != 'fc.terminal') module,
      ],
    );
    await plain.app.start();

    plain.app.left.setCursorToName('build.sh');
    expect(plain.commands.dispatch(KeyCombination.parse('Enter')), isTrue);
    await pumpEventQueue();

    expect(plain.app.view.contentAt(ViewportPosition.fullscreen), isNull);
  });
}
