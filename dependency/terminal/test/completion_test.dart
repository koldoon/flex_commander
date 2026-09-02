import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_modules.dart';

/// Дополнение путей по `Tab`.
///
/// Проверяется через настоящее приложение: подбор кандидатов идёт у провайдера
/// панели, а `Tab` принадлежит строке только пока ввод у неё.
late AppRuntime runtime;

Application get app => runtime.app;

CommandLineState get line => app.view.contentAt(ViewportPosition.bottom)! as CommandLineState;

bool press(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

/// Набирает строку так, как это делает человек: с курсором в конце.
void type(String command) =>
    line.text.value = TextEditingValue(text: command, selection: TextSelection.collapsed(offset: command.length));

Future<void> tab() async {
  press('Tab');
  await pumpEventQueue();
}

void main() {
  final pty = FakePty();

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider(
        [
          FakeEntry.directory('/home'),
          FakeEntry.directory('/home/docs'),
          FakeEntry.directory('/home/docs/deep'),
          FakeEntry.file('/home/docs/deep/inner.txt', size: 1),
          FakeEntry.directory('/home/downloads'),
          FakeEntry.directory('/home/.ssh'),
          FakeEntry.file('/home/dossier.txt', size: 1),
          FakeEntry.file('/home/notes.txt', size: 1),
          FakeEntry.file('/home/my report.txt', size: 1),
          FakeEntry.directory('/etc'),
          FakeEntry.file('/etc/passwd', size: 1),
        ],
        null,
        pty,
      )..home = '/home',
      modules: modulesWithTerminal(),
    );
    await runtime.app.start();
    press('Cmd-T');
  });

  test('единственный кандидат вставляется целиком, каталогу дописывается косая', () async {
    type('cat not');
    await tab();

    expect(line.text.text, 'cat notes.txt');

    line.clear();
    type('cd down');
    await tab();

    // Косая — чтобы следующий `Tab` пошёл внутрь.
    expect(line.text.text, 'cd downloads/');
  });

  test('из многих дописывается общее начало', () async {
    type('cat do');
    await tab();

    // `docs/`, `dossier.txt`, `downloads/` — общее начало `do`… уже набрано,
    // значит дописывать нечего; а вот `d` даёт `do`.
    line.clear();
    type('cat d');
    await tab();

    expect(line.text.text, 'cat do');
    expect(line.suggestions.map((c) => c.insertion), ['docs/', 'dossier.txt', 'downloads/']);
  });

  test('общего начала нет — Tab перебирает по кругу, Shift-Tab назад', () async {
    type('cat do');
    await tab();
    expect(line.text.text, 'cat docs/');

    await tab();
    expect(line.text.text, 'cat dossier.txt');

    await tab();
    expect(line.text.text, 'cat downloads/');

    // По кругу.
    await tab();
    expect(line.text.text, 'cat docs/');

    press('Shift-Tab');
    await pumpEventQueue();
    expect(line.text.text, 'cat downloads/');
  });

  test('правка обрывает перебор: следующий Tab — новый подбор', () async {
    type('cat do');
    await tab();
    expect(line.text.text, 'cat docs/');

    // Человек стёр и набрал другое.
    line.clear();
    type('cat not');
    await tab();

    expect(line.text.text, 'cat notes.txt');
  });

  test('подкаталог любой глубины', () async {
    type('cat docs/deep/in');
    await tab();

    expect(line.text.text, 'cat docs/deep/inner.txt');
  });

  test('путь от корня', () async {
    type('cat /etc/pas');
    await tab();

    expect(line.text.text, 'cat /etc/passwd');
  });

  test('тильда уводит в домашний каталог источника', () async {
    type('cat ~/not');
    await tab();

    expect(line.text.text, 'cat ~/notes.txt');
  });

  test('скрытые предлагаются только на точку', () async {
    type('cd s');
    await tab();
    expect(line.text.text, 'cd s', reason: '.ssh не должен предлагаться на «s»');
    expect(line.suggestions, isEmpty);

    line.clear();
    type('cd .s');
    await tab();
    expect(line.text.text, 'cd .ssh/');
  });

  test('имя с пробелом уезжает в кавычках', () async {
    type('cat my');
    await tab();

    expect(line.text.text, "cat 'my report.txt'");
  });

  test('кандидатов нет — строка не меняется вовсе', () async {
    type('cat zzz');
    await tab();

    expect(line.text.text, 'cat zzz');
    expect(line.suggestions, isEmpty);
  });

  test('пустой токен показывает всё, что здесь есть', () async {
    type('cat ');
    await tab();

    expect(line.suggestions.map((c) => c.insertion), [
      'docs/',
      'dossier.txt',
      'downloads/',
      'my report.txt',
      'notes.txt',
    ]);
  });

  test('дополняется то, что под курсором, а не конец строки', () async {
    line.text.value = const TextEditingValue(
      text: 'cp not /tmp',
      // Курсор сразу за `not`, а дальше ещё один аргумент.
      selection: TextSelection.collapsed(offset: 6),
    );
    await tab();

    expect(line.text.text, 'cp notes.txt /tmp');
  });

  group('пока идёт выбор', () {
    test('Enter закрепляет подставленное, а не выполняет команду', () async {
      type('cd do');
      await tab();
      expect(line.text.text, 'cd docs/');

      // Погружение продолжается: `Enter` закрывает выбор, строка остаётся.
      expect(press('Enter'), isTrue);
      await pumpEventQueue();

      expect(line.text.text, 'cd docs/');
      expect(line.suggestions, isEmpty);
      expect(line.history, isEmpty, reason: 'команда не выполнялась');

      // И следующий `Tab` идёт уже внутрь.
      await tab();
      expect(line.text.text, 'cd docs/deep/');
    });

    test('второй Enter уже выполняет', () async {
      type('cd do');
      await tab();
      press('Enter');
      await pumpEventQueue();

      press('Enter');
      await pumpEventQueue();

      // `cd` ведёт панель — значит она и переехала.
      expect(app.left.directory?.pathString, '/home/docs');
    });

    test('Esc возвращает набранное руками, а ввод оставляет в строке', () async {
      type('cat do');
      await tab();
      expect(line.text.text, 'cat docs/');

      expect(press('Esc'), isTrue);

      expect(line.text.text, 'cat do');
      expect(line.suggestions, isEmpty);
      expect(app.view.activeArea, ViewportPosition.bottom, reason: 'человек ещё не закончил');

      // А второй `Esc` — уже выход в панель.
      press('Esc');
      expect(app.view.activeArea, ViewportPosition.left);
    });
  });

  test('пока ввод у панели, Tab переключает панели', () async {
    press('Esc');
    expect(app.view.activeArea, ViewportPosition.left);

    expect(press('Tab'), isTrue);
    await pumpEventQueue();

    // Это и есть опора будущего режима `mc`: там ввод строке не отдаётся, и
    // `Tab` остаётся панельным без единой проверки настройки.
    expect(app.view.activeArea, ViewportPosition.right);
    expect(line.suggestions, isEmpty);
  });
}
