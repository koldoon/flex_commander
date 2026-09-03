import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/ui/remote_shell.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оболочка через границу: одна на место, байты в обе стороны, конец событием.
///
/// И главное — соединение держит **ядро**: панель вправе уйти с сервера хоть
/// сразу, а `htop`, запущенный там, обязан дожить до своего конца.
void main() {
  late FakePty pty;
  late InMemoryTreeProvider home;
  late ProviderRegistry registry;
  late CoreServer core;
  late Link link;
  late PanelSession left;
  late _Server? server;

  PanelSession sessionOn(ProviderRegistry registry) =>
      PanelSession(settings: PanelSettings.defaults('/home'), registry: registry, editor: const TreeTransferEngine());

  setUp(() async {
    pty = FakePty();
    home = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 3)], null, pty)
      ..home = '/home';
    registry = ProviderRegistry(root: home);
    // Сервер: монтируется адресом, как `ssh://`, — и закрывается, когда его
    // отпустил последний арендатор.
    server = null;
    registry.registerAddress(
      'tsh',
      () => CompletedOperation<Uri, TreeProvider>(server = _Server(pty, Uri.parse('tsh://tester@example.org/'))),
    );

    left = sessionOn(registry);
    core = CoreServer(left: left, right: sessionOn(registry), registry: registry);
    link = LoopbackLink(core);
    await link.call(const OpenPath(PanelId.left, '/home'));
  });

  tearDown(() async {
    await link.dispose();
    await core.dispose();
  });

  Future<ShellOpened> open({PanelId? panel = PanelId.left}) async {
    final reply = await link.call(OpenShell(panel: panel));
    expect(reply, isA<ShellOpened>(), reason: 'оболочка должна была открыться');
    return reply! as ShellOpened;
  }

  test('оболочка заводится там, где стоит панель', () async {
    final opened = await open();

    expect(pty.sessions, hasLength(1));
    expect(opened.label, 'localhost');
    expect(opened.fresh, isTrue);
  });

  test('вторая просьба отдаёт ту же оболочку, а не заводит вторую', () async {
    final first = await open();
    final again = await open();

    expect(pty.sessions, hasLength(1), reason: 'оболочка одна на место');
    expect(again.runId, first.runId, reason: 'разговор тот же — иначе это вторая оболочка');
    expect(again.fresh, isFalse, reason: 'уговор о метках второй раз не шлют');
  });

  test('байты идут в обе стороны', () async {
    final opened = await open();
    final shell = RemoteShell(link, opened.runId);
    final heard = <String>[];
    shell.output.listen((bytes) => heard.add(utf8.decode(bytes)));

    shell.write(Uint8List.fromList(utf8.encode('ls\n')));
    expect(pty.session.written, 'ls\n', reason: 'клавиши доехали до процесса');

    pty.session.emit('total 0\n');
    await pumpEventQueue();
    expect(heard, ['total 0\n'], reason: 'вывод доехал до экрана');
  });

  test('размер окна доезжает: без него `vim` считает, что перед ним 80×24', () async {
    final opened = await open();
    RemoteShell(link, opened.runId).resize(columns: 120, rows: 40);

    expect(pty.session.columns, 120);
    expect(pty.session.rows, 40);
  });

  test('оболочка кончилась — об этом говорят событием', () async {
    final opened = await open();
    final shell = RemoteShell(link, opened.runId);

    pty.session.exit(7);
    expect(await shell.exitCode, 7);
  });

  test('кончилась — следующая просьба заводит новую', () async {
    await open();
    pty.session.exit(0);
    await pumpEventQueue();

    final again = await open();
    expect(again.fresh, isTrue, reason: 'мёртвой слать команды некуда');
    expect(pty.sessions, hasLength(2));
  });

  test('выполнять негде — отказ, а не тишина', () async {
    // Источник без оболочки: внутри архива выполнять нечего, и сказать об этом
    // надо — клавишу нажали.
    // `InMemoryReadOnlyProvider` оболочки не объявляет — как её не объявляет
    // архив.
    final plain = sessionOn(
      ProviderRegistry(root: InMemoryReadOnlyProvider([FakeEntry.directory('/home')])..home = '/home'),
    );
    final other = CoreServer(left: plain, right: sessionOn(registry));
    final door = LoopbackLink(other);
    await door.call(const OpenPath(PanelId.left, '/home'));

    expect(await door.call(const OpenShell(panel: PanelId.left)), isA<CoreFailed>());

    await door.dispose();
    await other.dispose();
  });

  group('соединение держит ядро', () {
    setUp(() async {
      await link.call(const OpenPath(PanelId.left, 'tsh://tester@example.org/srv'));
      expect(left.provider, isA<_Server>(), reason: 'панель встала на сервер');
    });

    test('панель ушла с сервера, а оболочка жива — соединение держится', () async {
      await open();
      await link.call(const OpenPath(PanelId.left, '/home'));
      await pumpEventQueue();

      expect(server!.closed, isFalse, reason: 'htop на той стороне обязан дожить до своего конца');
    });

    test('оболочка кончилась — соединение отпущено', () async {
      await open();
      await link.call(const OpenPath(PanelId.left, '/home'));

      pty.session.exit(0);
      await pumpEventQueue();

      expect(server!.closed, isTrue, reason: 'держать сервер после `exit` незачем');
    });

    test('каталог панели приезжает так, как его назовёт сама оболочка', () async {
      // Путь панели — адрес (`//tester@example.org/srv`), а оболочка стоит на
      // сервере и про наши адреса не слышала.
      expect(left.state.shellDirectory, '/srv');
    });
  });
}

/// Сервер: дерево, смонтированное **адресом**, с оболочкой на той стороне.
///
/// Так же устроен `ssh://`: панель встаёт на него целиком, путь включает хост,
/// а оболочка про этот хост в пути ничего не знает — она уже там.
class _Server extends InMemoryAddressProvider implements ShellHost {
  _Server(this.pty, Uri address)
    : super(address: address, entries: [FakeEntry.directory('/srv'), FakeEntry.file('/srv/log.txt', size: 4)]);

  final FakePty pty;

  @override
  String get shellLabel => 'tester@example.org';

  @override
  String? get shellProgram => null;

  /// Путь без адреса: оболочка стоит на сервере и про наши адреса не слышала.
  @override
  String shellPath(String panelPath) {
    final prefix = '$scheme://${address.authority}';
    return panelPath.startsWith(prefix) ? panelPath.substring(prefix.length) : panelPath;
  }

  @override
  Future<PtySession> run(String command, {String? directory, int columns = 80, int rows = 24}) async =>
      pty.start(executable: 'sh', arguments: ['-c', command], columns: columns, rows: rows);

  @override
  Future<PtySession> shell({String? directory, int columns = 80, int rows = 24}) async =>
      pty.start(executable: 'sh', arguments: const [], columns: columns, rows: rows);
}
