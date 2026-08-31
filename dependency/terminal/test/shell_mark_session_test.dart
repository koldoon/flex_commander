import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Метка в живой сессии: доходит до приложения и не доходит до экрана.
void main() {
  late FakePtySession pty;
  late ShellAgreement agreement;
  late TerminalSession session;
  late List<ShellMark> marks;

  setUp(() {
    pty = FakePty().start(executable: '/bin/zsh') as FakePtySession;
    agreement = ShellAgreement(nonce: 'abcd');
    session = TerminalSession.around(pty, agreement: agreement);
    marks = [];
    session.onMark = marks.add;
  });

  tearDown(() => session.dispose());

  String mark(int code, String directory) => '\x1b]777;fc;abcd;$code;$directory\x07';

  String screen() => session.terminal.buffer.getText().trim();

  test('метка доходит до приложения', () async {
    pty.emit(mark(0, '/home/koldoon'));
    await pumpEventQueue();

    expect(marks, hasLength(1));
    expect(marks.single.exitCode, 0);
    expect(marks.single.directory, '/home/koldoon');
    expect(session.lastMark?.exitCode, 0);
  });

  test('на экране её не видно', () async {
    // Не потому, что мы её вычищаем: OSC — управляющая последовательность, и
    // разбор терминала съедает её целиком.
    pty.emit('hello\r\n${mark(0, '/tmp')}world');
    await pumpEventQueue();

    expect(screen(), 'hello\nworld');
    expect(screen(), isNot(contains('777')));
    expect(screen(), isNot(contains('abcd')));
  });

  test('чужая метка не считается', () async {
    pty.emit('\x1b]777;fc;ffff;0;/tmp\x07');
    await pumpEventQueue();

    expect(marks, isEmpty);
    expect(session.lastMark, isNull);
  });

  test('каждое приглашение приносит свою метку', () async {
    pty.emit(mark(0, '/tmp'));
    pty.emit(mark(1, '/tmp/inner'));
    await pumpEventQueue();

    expect(marks.map((it) => it.exitCode), [0, 1]);
    expect(session.lastMark?.directory, '/tmp/inner');
  });

  test('без уговора метка молчит', () async {
    // Разовый запуск сессию не уговаривает: конец команды он и так знает.
    final bare = TerminalSession.around(pty);
    addTearDown(bare.dispose);

    pty.emit(mark(0, '/tmp'));
    await pumpEventQueue();

    expect(bare.lastMark, isNull);
  });
}
