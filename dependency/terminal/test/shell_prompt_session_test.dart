import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Приглашение в живой сессии: снимается после метки, когда печать утихла
/// (`docs/spec/shell-prompt.md`, §4).
void main() {
  late FakePtySession pty;
  late TerminalSession session;

  setUp(() {
    pty = FakePty().start(executable: '/bin/zsh') as FakePtySession;
    session = TerminalSession.around(pty, agreement: ShellAgreement(nonce: 'abcd'));
  });

  tearDown(() => session.dispose());

  String prompt(int code, String directory) => '\x1b]777;fc;abcd;p;$code;$directory\x07';
  const String running = '\x1b]777;fc;abcd;r\x07';

  /// Дождаться тишины: столько же ждёт и сама сессия.
  Future<void> settle() async {
    await pumpEventQueue();
    await Future<void>.delayed(TerminalSession.promptSettleDelay * 2);
    await pumpEventQueue();
  }

  test('после метки и паузы приглашение снято', () async {
    pty.emit('${prompt(0, '/tmp')}koldoon@cray /tmp \$ ');
    await settle();

    expect(session.prompt.lastText, r'koldoon@cray /tmp $');
  });

  test('до паузы приглашение ещё не снято: печать идёт кусками', () async {
    pty.emit('${prompt(0, '/tmp')}koldoon');
    await pumpEventQueue();

    expect(session.prompt.isEmpty, isTrue, reason: 'снятое на первой записи было бы половиной');

    pty.emit('@cray /tmp \$ ');
    await settle();

    expect(session.prompt.lastText, r'koldoon@cray /tmp $');
  });

  test('вывод команды приглашением не становится', () async {
    pty.emit('${prompt(0, '/tmp')}\$ ');
    await settle();

    pty.emit('$running\r\nчто-то вывелось\r\n');
    await settle();

    expect(session.prompt.lastText, r'$', reason: 'осталось прежнее: новое ещё не печатали');
  });

  test('новое приглашение заменяет прежнее', () async {
    pty.emit('${prompt(0, '/tmp')}/tmp \$ ');
    await settle();

    pty.emit('$running\r\n${prompt(0, '/home')}/home \$ ');
    await settle();

    expect(session.prompt.lastText, r'/home $');
  });

  test('цвета приглашения доезжают', () async {
    pty.emit('${prompt(0, '/tmp')}\x1b[32m/tmp\x1b[0m \$ ');
    await settle();

    final runs = session.prompt.lastLine;
    expect(runs.first.text, '/tmp');
    expect(runs.first.color, isNot(runs.last.color));
  });
}
