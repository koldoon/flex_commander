import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/state/elevation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оболочка, у которой видно каждую запущенную команду и назначен её исход.
class _RecordingHost implements ShellHost {
  _RecordingHost({this.needsPassword = true});

  @override
  String get shellLabel => 'tester@shark';

  @override
  String? get shellProgram => null;

  @override
  String shellPath(String panelPath) => panelPath;

  /// Нужен ли пароль: от этого зависит исход `sudo -n true`.
  final bool needsPassword;

  /// Какой пароль сервер принимает.
  static const String rightPassword = 'верный';

  final List<String> commands = [];
  final List<FakePtySession> sessions = [];

  @override
  Future<PtySession> run(String command, {String? directory, int columns = 80, int rows = 24}) async {
    commands.add(command);
    final session = FakePtySession(
      executable: 'sh',
      arguments: ['-lic', command],
      workingDirectory: directory,
      environment: const {},
      columns: columns,
      rows: rows,
    );
    sessions.add(session);

    if (command == 'sudo -n true') {
      // Пароль нужен — значит `sudo -n` не проходит.
      scheduleMicrotask(() => session.exit(needsPassword ? 1 : 0));
      return session;
    }

    // Копирование. Пароля не спрашивали — проходит и без ввода: так ведёт себя
    // `sudo` с живым тикетом или `NOPASSWD`.
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        await pumpEventQueue(times: 1);
        final ok = !needsPassword || session.written.trim() == rightPassword;
        session.exit(ok ? 0 : 1);
      }),
    );
    return session;
  }

  @override
  Future<PtySession> shell({String? directory, int columns = 80, int rows = 24}) => throw UnimplementedError();
}

void main() {
  late FakeCredentials credentials;
  late _RecordingHost host;

  const about = ElevationRequest(action: 'Save', path: '/etc/squid/squid.conf', where: 'tester@shark');

  setUp(() {
    credentials = FakeCredentials();
    host = _RecordingHost();
  });

  /// Подставные секреты с заданными ответами.
  void answering(List<String?> answers) => credentials = FakeCredentials(answers: answers);

  ElevationController controller({bool allowed = true}) =>
      ElevationController(credentials: credentials, allowed: () => allowed);

  /// Согласиться на предложение, как только его зададут.
  Future<void> agree(ElevationController elevation, {bool yes = true}) async {
    await pumpEventQueue();
    expect(elevation.pending, isNotNull, reason: 'согласие спрашивается всегда');
    elevation.answer(yes);
  }

  test('выключенное повышение не спрашивает и не выполняет ничего', () async {
    final elevation = controller(allowed: false);

    expect(await elevation.copyOver(host: host, temporary: '/tmp/x', target: '/etc/x', about: about), isFalse);
    expect(elevation.pending, isNull);
    expect(host.commands, isEmpty, reason: 'на общей машине это единственный честный ответ');
  });

  test('согласие спрашивается раньше всего, и отказ ничего не запускает', () async {
    final elevation = controller();
    final work = elevation.copyOver(host: host, temporary: '/tmp/x', target: '/etc/x', about: about);
    await agree(elevation, yes: false);

    expect(await work, isFalse);
    expect(host.commands, isEmpty, reason: 'цель не тронута');
  });

  test('пароль не нужен — окна пароля нет, а подтверждение есть', () async {
    host = _RecordingHost(needsPassword: false);
    final elevation = controller();

    final work = elevation.copyOver(host: host, temporary: '/tmp/x', target: '/etc/x', about: about);
    await agree(elevation);

    expect(await work, isTrue);
    expect(credentials.asked, isEmpty, reason: 'тикет sudo ещё жив или стоит NOPASSWD');
    expect(host.commands.first, 'sudo -n true');
  });

  test('пароль уходит записью в псевдотерминал, а не аргументом', () async {
    answering(['верный']);
    final elevation = controller();

    final work = elevation.copyOver(host: host, temporary: '/tmp/x', target: '/etc/x', about: about);
    await agree(elevation);

    expect(await work, isTrue);
    // Аргументы видно в `ps` всей машине — пароля там быть не должно.
    expect(host.commands.join(' '), isNot(contains('верный')));
    expect(host.sessions.last.written.trim(), 'верный');
  });

  test('копирует, а не переименовывает, и пути закавычены', () async {
    answering(['верный']);
    final elevation = controller();

    final work = elevation.copyOver(host: host, temporary: "/tmp/it's", target: '/etc/squid/squid.conf', about: about);
    await agree(elevation);
    await work;

    final copy = host.commands.last;
    // Переименование от root отдало бы файл root и потеряло исходные права.
    expect(copy, startsWith('sudo -S -p "" cp -- '));
    // `--` уже есть выше; кавычки — чтобы апостроф не разваливал команду.
    expect(copy, contains(r"'/tmp/it'\''s'"));
  });

  test('неверный пароль забывается и спрашивается ещё раз', () async {
    answering(['не тот', 'снова не тот']);
    final elevation = controller();

    final work = elevation.copyOver(host: host, temporary: '/tmp/x', target: '/etc/x', about: about);
    await agree(elevation);

    await expectLater(work, throwsA(isA<FsError>()));
    expect(credentials.asked, hasLength(2), reason: 'второй раз — уже как повтор');
    expect(credentials.asked.last.retry, isTrue);
    expect(credentials.known, isEmpty, reason: 'не подошедший пароль не запоминается');
  });

  test('отказ от окна пароля не трогает цель', () async {
    answering([]);
    final elevation = controller();

    final work = elevation.copyOver(host: host, temporary: '/tmp/x', target: '/etc/x', about: about);
    await agree(elevation);

    expect(await work, isFalse);
    expect(host.commands, ['sudo -n true'], reason: 'до копирования дело не дошло');
  });

  test('пароль помнится по машинам порознь', () {
    expect(about.realm, 'sudo:tester@shark');
    expect(
      const ElevationRequest(action: 'Save', path: '/etc/x', where: 'localhost').realm,
      'sudo:localhost',
      reason: 'один пароль на все серверы — способ отправить его туда, где не ждали',
    );
  });
}
