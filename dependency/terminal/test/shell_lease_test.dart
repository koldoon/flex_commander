import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Аренда, которая считает, сколько раз её отпустили.
class _CountingLease implements ProviderLease {
  int released = 0;

  @override
  TreeProvider get provider => throw UnimplementedError('тесту провайдер не нужен');

  @override
  Future<void> release() async => released++;
}

/// Оболочка на сервере держит источник, пока жива.
///
/// Иначе уход панели с сервера закрыл бы соединение из-под работающего `htop`.
void main() {
  late FakePty pty;
  late _CountingLease lease;

  setUp(() {
    pty = FakePty();
    lease = _CountingLease();
  });

  TerminalSession sessionWithLease() =>
      TerminalSession.around(pty.start(executable: 'sh', arguments: const []), lease: lease);

  test('пока оболочка жива, источник не отпускается', () async {
    sessionWithLease();
    await pumpEventQueue();

    expect(lease.released, 0);
  });

  test('оболочка кончилась сама — источник отпущен', () async {
    sessionWithLease();
    pty.session.exit(0);
    await pumpEventQueue();

    // Держать сервер после `exit` незачем: оболочки на нём больше нет.
    expect(lease.released, 1);
  });

  test('закрыли сессию — источник отпущен, и ровно один раз', () async {
    final session = sessionWithLease();
    session.dispose();
    await pumpEventQueue();

    // Отпускают в двух местах — на конце оболочки и на закрытии, — и оба
    // срабатывают при закрытии живой сессии. Отпускание одноразовое.
    expect(lease.released, 1);
  });

  test('кончилась, а потом закрыли — всё равно один раз', () async {
    final session = sessionWithLease();
    pty.session.exit(0);
    await pumpEventQueue();
    session.dispose();
    await pumpEventQueue();

    expect(lease.released, 1);
  });

  group('таблица оболочек', () {
    TerminalSettings options() => TerminalSettings();

    test('вторая просьба об оболочке отпускает лишнюю аренду сразу', () async {
      final shells = ShellSession(settings: options);
      final host = InMemoryTreeProvider([FakeEntry.directory('/home')], null, pty);

      final first = await shells.sessionIn(host, '/home', lease: lease);

      final extra = _CountingLease();
      final again = await shells.sessionIn(host, '/home', lease: extra);

      expect(again, same(first), reason: 'оболочка та же — заводить вторую незачем');
      expect(extra.released, 1, reason: 'иначе сервер не отпустить никогда');
      expect(lease.released, 0, reason: 'аренда живой сессии остаётся при ней');

      shells.close();
    });

    test('свежая оболочка встречает уговор о метках, и его не видно', () async {
      final shells = ShellSession(settings: options);
      final host = InMemoryTreeProvider([FakeEntry.directory('/home')], null, pty);

      await shells.sessionIn(host, '/home');
      await pumpEventQueue();

      // Уговор уходит в **уже запущенную** сессию, а не в чужой конфиг: живёт
      // он ровно столько, сколько она.
      final sent = pty.session.written;
      expect(sent, contains('777;fc;'), reason: 'метка с числом этой сессии');
      expect(sent, contains(r'$BASH_VERSION'), reason: 'общая строка разбирается изнутри');
      // Сама строка уговора в ленте не нужна — всё, что после неё, уже жизнь
      // человека.
      expect(sent, endsWith('clear\n'));

      shells.close();
    });

    test('не открылась — аренду не держим', () async {
      final shells = ShellSession(settings: options);
      final host = _RefusingHost();

      await expectLater(shells.sessionIn(host, '/home', lease: lease), throwsA(isA<StateError>()));
      expect(lease.released, 1);
    });
  });
}

/// Оболочка, которая не открывается: так ведёт себя недоступный сервер.
class _RefusingHost implements ShellHost {
  @override
  String get shellLabel => 'tester@example.org';

  @override
  String? get shellProgram => null;

  @override
  String shellPath(String panelPath) => panelPath;

  @override
  Future<PtySession> run(String command, {String? directory, int columns = 80, int rows = 24}) =>
      throw StateError('нет связи');

  @override
  Future<PtySession> shell({String? directory, int columns = 80, int rows = 24}) => throw StateError('нет связи');
}
