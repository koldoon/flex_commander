import 'package:fc_api/fc_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Командная строка: что уходит в оболочку, а что — панели.
///
/// Настоящей оболочки здесь нет: [FakePty] записывает, с чем её позвали, и
/// говорит то, что велит тест.
late AppRuntime runtime;
late FakePty pty;

Application get app => runtime.app;

CommandLineState get line => app.view.contentAt(ViewportPosition.bottom)! as CommandLineState;

bool press(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

void type(String command) => line.text.text = command;

void main() {
  setUp(() async {
    // Приложение живёт на macOS, и клавиши разбираются по-разному: там, где
    // `Cmd` играет `Ctrl`, `Cmd-O` («открыть в системе») и наш `Ctrl-O`
    // оказываются одной и той же комбинацией. Проверять надо то, что поедет к
    // людям, а не то, во что это превращается в подставной платформе теста.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    pty = FakePty();
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/my report.txt', size: 10),
      ])..home = '/home',
      // Свой модуль вместо того, что стоит в приложении: у этого псевдотерминал
      // подставной. Два одинаковых модуля спорили бы за одну и ту же службу.
      modules: [...featureModules().where((module) => module.id != 'fc.terminal'), ShellTerminal(pty: pty)],
    );
    await runtime.app.start();
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('строка стоит внизу с самого запуска', () {
    expect(app.view.contentAt(ViewportPosition.bottom), isA<CommandLineState>());
    expect(line.prompt, '/home');
    expect(line.enabled, isTrue);
  });

  test('Cmd-T отдаёт ей ввод, Esc возвращает панели', () {
    expect(press('Cmd-T'), isTrue);
    expect(app.view.activeArea, ViewportPosition.bottom);

    expect(press('Esc'), isTrue);
    expect(app.view.activeArea, ViewportPosition.left);
  });

  test('Esc набранное не стирает: вернуться — то же одно нажатие', () {
    press('Cmd-T');
    type('make');
    press('Esc');

    expect(line.text.text, 'make');
  });

  group('запуск', () {
    test('команда уходит оболочке в каталоге панели — и без всякого cd', () async {
      press('Cmd-T');
      type('ls -la');
      expect(press('Enter'), isTrue);
      await pumpEventQueue();

      final session = pty.session;
      expect(session.arguments.last, 'ls -la');
      expect(session.workingDirectory, '/home');
      // Каталог — параметр запуска, а не строка, отправленная оболочке.
      expect(session.written, isEmpty);
    });

    test('строка очищается и помнит выполненное', () async {
      press('Cmd-T');
      type('ls');
      press('Enter');
      await pumpEventQueue();

      expect(line.text.text, isEmpty);
      expect(line.history, ['ls']);
    });

    test('пустая строка ничего не выполняет — но Enter забирает себе', () {
      press('Cmd-T');
      type('   ');

      // `true`, а не `false`: иначе `Enter` провалился бы в поле, а оно на нём
      // снимает с себя фокус — курсор пропадал, ввод оставался за строкой, и
      // клавиши панели молчали до самого `Esc`.
      expect(press('Enter'), isTrue);
      expect(pty.started, isFalse);
      expect(app.view.activeArea, ViewportPosition.bottom);
    });

    test('молчаливая успешная команда экрана не показывает', () async {
      press('Cmd-T');
      type('mkdir new');
      press('Enter');
      await pumpEventQueue();

      pty.session.exit(0);
      await pumpEventQueue();

      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);
    });

    test('сказавшая хоть слово — показывает и остаётся', () async {
      press('Cmd-T');
      type('git status');
      press('Enter');
      await pumpEventQueue();

      pty.session.emit('On branch master\r\n');
      await pumpEventQueue();

      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<CommandRunScreen>());
      expect((screen! as CommandRunScreen).session.terminal.buffer.getText(), contains('On branch master'));

      pty.session.exit(0);
      await pumpEventQueue();

      // Вывод прочитать не успели бы, закройся экран сам.
      expect(app.view.contentAt(ViewportPosition.fullscreen), same(screen));
    });

    test('провалившаяся показывает код, даже если промолчала', () async {
      press('Cmd-T');
      type('false');
      press('Enter');
      await pumpEventQueue();

      pty.session.exit(3);
      await pumpEventQueue();

      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<CommandRunScreen>());
      expect((screen! as CommandRunScreen).exitCode, 3);
    });

    test('экран убирается клавишей — но только после конца команды', () async {
      press('Cmd-T');
      type('cat');
      press('Enter');
      await pumpEventQueue();
      pty.session.emit('ждём\r\n');
      await pumpEventQueue();

      // Пока команда работает, Enter принадлежит ей: она может о чём-то
      // спрашивать.
      expect(press('Enter'), isFalse);
      expect(app.view.contentAt(ViewportPosition.fullscreen), isA<CommandRunScreen>());

      pty.session.exit(0);
      await pumpEventQueue();

      expect(press('Enter'), isTrue);
      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);
    });
  });

  group('cd ведёт панель', () {
    test('cd с путём переводит панель, а оболочку не трогает', () async {
      press('Cmd-T');
      type('cd docs');
      press('Enter');
      await pumpEventQueue();

      expect(app.left.directory?.pathString, '/home/docs');
      expect(pty.started, isFalse);
      expect(line.history, ['cd docs']);
    });

    test('cd без аргументов уводит домой', () async {
      await app.left.openPath('/home/docs');
      press('Cmd-T');
      type('cd');
      press('Enter');
      await pumpEventQueue();

      expect(app.left.directory?.pathString, '/home');
      expect(pty.started, isFalse);
    });

    test('cd с продолжением толковать не беремся — уходит оболочке', () async {
      press('Cmd-T');
      type('cd docs && make');
      press('Enter');
      await pumpEventQueue();

      expect(pty.session.arguments.last, 'cd docs && make');
      expect(app.left.directory?.pathString, '/home');
    });
  });

  group('вставка и история', () {
    test('пробел ставится только между словом и именем', () {
      press('Cmd-T');
      app.left.setCursorToName('docs');

      // Кончилось слово — нужен разделитель.
      type('rm');
      press('Cmd-Enter');
      expect(line.text.text, 'rm docs');

      // А это начало самого имени: `./` и файл должны слипнуться.
      line.clear();
      type('./');
      press('Cmd-Enter');
      expect(line.text.text, './docs');

      line.clear();
      type('--out=');
      press('Cmd-Enter');
      expect(line.text.text, '--out=docs');

      // Пустая строка и уже поставленный пробел лишнего не получают.
      line.clear();
      press('Cmd-Enter');
      expect(line.text.text, 'docs');

      line.clear();
      type('cat ');
      press('Cmd-Enter');
      expect(line.text.text, 'cat docs');
    });

    test('Cmd-Enter вставляет имя, Cmd-Shift-Enter — путь', () {
      press('Cmd-T');
      app.left.setCursorToName('my report.txt');
      type('rm');

      press('Cmd-Enter');
      expect(line.text.text, "rm 'my report.txt'");

      line.clear();
      type('cat');
      press('Cmd-Shift-Enter');
      expect(line.text.text, "cat '/home/my report.txt'");
    });

    test('история ходит вверх и вниз и возвращает набранное', () async {
      press('Cmd-T');
      type('first');
      press('Enter');
      await pumpEventQueue();
      pty.session.exit(0);
      await pumpEventQueue();

      type('набранное');
      press('Cmd-Up');
      expect(line.text.text, 'first');

      press('Cmd-Down');
      expect(line.text.text, 'набранное');
    });

    test('подряд повторённая команда не удваивается', () async {
      for (var i = 0; i < 2; i++) {
        press('Cmd-T');
        type('make');
        press('Enter');
        await pumpEventQueue();
        pty.sessions.last.exit(0);
        await pumpEventQueue();
      }

      expect(line.history, ['make']);
    });
  });

  test('на источнике без настоящих путей строка приглушена', () async {
    // Архив и `ssh://`: выполнить команду «в этом каталоге» негде, а сделать
    // вид, что она выполнится там, где показано, — худшее из возможного.
    // Второе приложение поверх собранного в setUp: разбирать его — дело
    // `testApp`, он это делает сам после теста.
    pty = FakePty();
    runtime = await testApp(
      provider: InMemoryReadOnlyProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: [...featureModules().where((module) => module.id != 'fc.terminal'), ShellTerminal(pty: pty)],
    );
    await runtime.app.start();

    expect(line.enabled, isFalse);
    expect(line.workingDirectory, isNull);

    // И ввод ей не отдаётся: поля нет, курсору взяться неоткуда, а клавиши
    // панели должны работать.
    expect(press('Cmd-T'), isFalse);
    expect(app.view.activeArea, ViewportPosition.left);
    expect(pty.started, isFalse);
  });

  group('терминал', () {
    test('Ctrl-O разворачивает сессию и сворачивает обратно', () {
      expect(pty.started, isFalse, reason: 'оболочка не должна заводиться при сборке');

      expect(press('Ctrl-O'), isTrue);
      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<TerminalScreen>());
      expect(pty.started, isTrue);

      press('Ctrl-O');
      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);

      // Та же сессия, а не вторая: свернули вид, а не оболочку.
      press('Ctrl-O');
      expect(pty.sessions, hasLength(1));
      expect(
        (app.view.contentAt(ViewportPosition.fullscreen)! as TerminalScreen).session,
        same((screen! as TerminalScreen).session),
      );
    });

    test('оболочка начинает там, где стояла панель', () {
      press('Ctrl-O');

      expect(pty.session.workingDirectory, '/home');
      expect(pty.session.arguments, contains('-i'));
    });
  });
}
