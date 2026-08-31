import 'package:fc_api/fc_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_modules.dart';

/// Командная строка: что уходит в оболочку, а что — панели.
///
/// Настоящей оболочки здесь нет: [FakePty] записывает, с чем её позвали, и
/// говорит то, что велит тест.
late AppRuntime runtime;
late FakePty pty;
late InMemoryTreeProvider provider;

Application get app => runtime.app;

CommandLineState get line => app.view.contentAt(ViewportPosition.bottom)! as CommandLineState;

bool press(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

void type(String command) => line.text.text = command;

/// Подставная оболочка, которая держит уговор: без неё приложение не узнает ни
/// конца команды, ни её кода.
///
/// Одна на прогон: она помнит, отметилась ли уже о запуске, — настоящая тоже
/// не отмечается дважды.
AgreeingShell? _shell;
AgreeingShell get shell => _shell ??= AgreeingShell(pty.session);

/// Нажать `Enter` и довести отправку до оболочки.
///
/// Первое приглашение подставная оболочка печатает только один раз — при
/// запуске. Второе было бы враньём и, хуже того, сошло бы за конец команды,
/// которую только что отправили.
Future<void> submit() async {
  final fresh = _shell == null;
  press('Enter');
  await pumpEventQueue();
  if (fresh) {
    shell.greet();
    await pumpEventQueue();
  }
}

void main() {
  setUp(() async {
    // Приложение живёт на macOS, и клавиши разбираются по-разному: там, где
    // `Cmd` играет `Ctrl`, `Cmd-O` («открыть в системе») и наш `Ctrl-O`
    // оказываются одной и той же комбинацией. Проверять надо то, что поедет к
    // людям, а не то, во что это превращается в подставной платформе теста.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    pty = FakePty();
    _shell = null;
    provider = InMemoryTreeProvider(
      [
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/my report.txt', size: 10),
      ],
      null,
      pty,
    )..home = '/home';
    runtime = await testApp(
      provider: provider,
      // Псевдотерминал здесь подставной — его даёт сам провайдер: оболочка
      // это умение источника, а не служба приложения.
      modules: modulesWithTerminal(),
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
    test('команда уходит в ту же оболочку строкой, а не своим процессом', () async {
      press('Cmd-T');
      type('ls -la');
      await submit();

      final session = pty.session;
      expect(session.arguments.last, '-i', reason: 'сессия — оболочка, а не наша команда');
      expect(session.written, contains('ls -la\n'));
      expect(pty.sessions, hasLength(1), reason: 'на команду вторая оболочка не заводится');
    });

    test('каталог не досылается, пока оболочка стоит там же', () async {
      press('Cmd-T');
      type('ls');
      await submit();

      // Где стоит оболочка, известно точно — из метки; гонять её туда-сюда на
      // каждую команду незачем.
      expect(pty.session.written, isNot(contains('cd ')));
    });

    test('строка очищается и помнит выполненное', () async {
      press('Cmd-T');
      type('ls');
      await submit();

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

    test('прерванная человеком команда уходит с экрана сама', () async {
      press('Cmd-T');
      type('tail -f log');
      await submit();
      shell.start();
      pty.session.emit('первая строка\r\n');
      await pumpEventQueue();

      final screen = app.view.contentAt(ViewportPosition.fullscreen)! as CommandRunScreen;

      // Тем же путём, что и с клавиатуры: `xterm` зовёт `onOutput`, а сессия
      // отправляет байт программе.
      screen.session.terminal.onOutput!('\x03');
      pty.session.emit('^C');
      shell.finish(code: 130);
      await pumpEventQueue();

      // Раньше здесь оставался экран с `^C` и ждал ещё одного нажатия: со
      // стороны это выглядело как «`Ctrl-C` не сработал».
      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);
    });

    test('Ctrl-O убирает работающую команду с глаз, а не ставит вторую оболочку', () async {
      press('Cmd-T');
      type('tail -f log');
      await submit();
      shell.start();
      pty.session.emit('первая строка\r\n');
      await pumpEventQueue();

      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<CommandRunScreen>());

      // Раньше поверх работающей команды вставал второй полноэкранный терминал:
      // выглядело это как два одинаковых экрана, между которыми и переключаешься.
      expect(press('Ctrl-O'), isTrue);
      await pumpEventQueue();
      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);
      expect(pty.sessions, hasLength(1), reason: 'второй оболочки не заводится');
      expect(pty.session.killed, isFalse, reason: 'процесс продолжает работать');

      // Обратно — туда же, откуда ушли, и к тому же самому экрану.
      expect(press('Ctrl-O'), isTrue);
      await pumpEventQueue();
      expect(app.view.contentAt(ViewportPosition.fullscreen), same(screen));

      shell.finish();
      await pumpEventQueue();
      expect(press('Esc'), isTrue);
      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);
    });

    test('молчаливая успешная команда экрана не показывает', () async {
      press('Cmd-T');
      type('mkdir new');
      await submit();

      shell.finish();
      await pumpEventQueue();

      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);
    });

    test('сказавшая хоть слово — показывает и остаётся', () async {
      press('Cmd-T');
      type('git status');
      await submit();

      shell.start();
      pty.session.emit('On branch master\r\n');
      await pumpEventQueue();

      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<CommandRunScreen>());
      expect((screen! as CommandRunScreen).session.terminal.buffer.getText(), contains('On branch master'));

      shell.finish();
      await pumpEventQueue();

      // Вывод прочитать не успели бы, закройся экран сам.
      expect(app.view.contentAt(ViewportPosition.fullscreen), same(screen));
    });

    test('провалившаяся показывает код, даже если промолчала', () async {
      press('Cmd-T');
      type('false');
      await submit();

      shell.finish(code: 3);
      await pumpEventQueue();

      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<CommandRunScreen>());
      expect((screen! as CommandRunScreen).exitCode, 3);
    });

    test('экран убирается клавишей — но только после конца команды', () async {
      press('Cmd-T');
      type('cat');
      await submit();
      shell.start();
      pty.session.emit('ждём\r\n');
      await pumpEventQueue();

      // Пока команда работает, Enter принадлежит ей: она может о чём-то
      // спрашивать.
      expect(press('Enter'), isFalse);
      expect(app.view.contentAt(ViewportPosition.fullscreen), isA<CommandRunScreen>());

      shell.finish();
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
      await submit();

      expect(pty.session.written, contains('cd docs && make\n'));
      expect(app.left.directory?.pathString, '/home');
    });

    test('оболочка ушла сама — панель идёт следом', () async {
      press('Cmd-T');
      type('cd docs && make');
      await submit();

      // Строку с продолжением мы не толкуем, но куда оболочка встала, метка
      // говорит точно: оставлять панель позади незачем.
      shell.finish(directory: '/home/docs');
      await pumpEventQueue();

      expect(app.left.directory?.pathString, '/home/docs');
    });

    test('оболочка стоит там же — панель не трогают', () async {
      press('Cmd-T');
      type('make');
      await submit();

      shell.finish();
      await pumpEventQueue();

      expect(app.left.directory?.pathString, '/home');
    });

    test('«убрать сразу» уносит экран успешной команды, но не провалившейся', () async {
      line.settings.afterCommand = TerminalSettings.hideAfterCommand;

      press('Cmd-T');
      type('git status');
      await submit();
      shell.finish(output: 'On branch master\r\n');
      await pumpEventQueue();

      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull, reason: 'успешная уходит сама');

      press('Cmd-T');
      type('false');
      await submit();
      shell.finish(code: 3);
      await pumpEventQueue();

      // Код возврата — единственное, о чём точно нужно сказать, и убирать его
      // с глаз по настройке нельзя.
      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<CommandRunScreen>());
      expect((screen! as CommandRunScreen).exitCode, 3);
    });

    test('оболочка умерла — следующая команда заводит новую', () async {
      press('Cmd-T');
      type('exit');
      await submit();
      pty.session.exit(0);
      await pumpEventQueue();

      _shell = null;
      press('Cmd-T');
      type('ls');
      press('Enter');
      await pumpEventQueue();

      expect(pty.sessions, hasLength(2), reason: 'мёртвую держать незачем');
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
      await submit();
      shell.finish();
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
        await submit();
        shell.finish();
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
      // Обычное дерево, без оболочки: `ShellHost` оно не объявляет — как не
      // объявляет его архив.
      provider: InMemoryReadOnlyProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: modulesWithTerminal(),
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

  group('приглашение', () {
    test('на своей машине — просто путь', () {
      expect(line.prompt, '/home');
    });

    test('на сервере видно, где выполнится набранное', () async {
      // Иначе `rm` на сервере не отличить от `rm` у себя — а это ровно тот
      // случай, когда ошибиться нельзя.
      provider.shellLabel = 'tester@example.org';
      await pumpEventQueue();

      expect(line.prompt, 'tester@example.org:/home');
      expect(line.enabled, isTrue);
    });
  });

  group('терминал', () {
    test('Ctrl-O разворачивает сессию и сворачивает обратно', () async {
      expect(pty.started, isFalse, reason: 'оболочка не должна заводиться при сборке');

      // Открытие ждут: на сервере это поход по сети, и оттого асинхронно даже
      // на своей машине — повадка у оболочек одна.
      expect(press('Ctrl-O'), isTrue);
      await pumpEventQueue();

      // И показывают не раньше, чем оболочка убрала с глаз строку уговора.
      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull, reason: 'пока уговор на экране — не показываем');
      shell.greet();
      await pumpEventQueue();

      final screen = app.view.contentAt(ViewportPosition.fullscreen);
      expect(screen, isA<TerminalScreen>());
      expect(pty.started, isTrue);

      press('Ctrl-O');
      await pumpEventQueue();
      expect(app.view.contentAt(ViewportPosition.fullscreen), isNull);

      // Та же сессия, а не вторая: свернули вид, а не оболочку.
      press('Ctrl-O');
      await pumpEventQueue();
      expect(pty.sessions, hasLength(1));
      expect(
        (app.view.contentAt(ViewportPosition.fullscreen)! as TerminalScreen).session,
        same((screen! as TerminalScreen).session),
      );
    });

    test('оболочка начинает там, где стояла панель', () async {
      press('Ctrl-O');
      await pumpEventQueue();

      expect(pty.session.workingDirectory, '/home');
      expect(pty.session.arguments, contains('-i'));
    });
  });
}
