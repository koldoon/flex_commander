import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Псевдотерминал по-настоящему: не подставка, а `/bin/sh` в живом pty.
///
/// Такой тест стал возможен ровно потому, что нативной части больше нет:
/// `posix_openpt` и `posix_spawn` лежат в системе, и прогон на хостовой машине
/// до них дотягивается. С плагином здесь была бы «Failed to load dynamic
/// library».
void main() {
  /// Запускает команду и собирает всё, что она сказала, до самого конца.
  Future<(String, int)> run(String command, {String? directory, int columns = 80, int rows = 24}) async {
    final session = const SystemPtyLauncher().start(
      executable: '/bin/sh',
      arguments: ['-c', command],
      workingDirectory: directory,
      environment: const {'TERM': 'dumb', 'LANG': 'en_US.UTF-8'},
      columns: columns,
      rows: rows,
    );

    final output = StringBuffer();
    final done =
        session.output.listen((chunk) => output.write(utf8.decode(chunk, allowMalformed: true))).asFuture<void>();
    final code = await session.exitCode;
    // Конец вывода приходит после конца программы: дочитываем.
    await done.timeout(const Duration(seconds: 5), onTimeout: () {});
    return (output.toString(), code);
  }

  test('программа говорит, и её слышно', () async {
    final (text, code) = await run('echo привет');

    expect(text, contains('привет'));
    expect(code, 0);
  });

  test('Ctrl-C прерывает программу, а не только печатает ^C', () async {
    final session = const SystemPtyLauncher().start(
      executable: '/bin/cat',
      environment: const {'TERM': 'dumb', 'LANG': 'en_US.UTF-8'},
    );
    // `cat` без аргументов ждёт ввода вечно — как раз то, из чего человек и
    // выходит по `Ctrl-C`.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    session.write(Uint8List.fromList([3]));

    // Сигнал шлёт драйвер терминала — той группе процессов, что стоит у него на
    // переднем плане. Пока у программы не было **управляющего** терминала,
    // группы этой не существовало вовсе: `^C` исправно печатался, а `SIGINT`
    // слать было некому, и выйти из `cat` было нельзя ничем, кроме `kill`.
    await expectLater(session.exitCode.timeout(const Duration(seconds: 5)), completes);
  });

  test('код возврата доходит целым', () async {
    final (_, code) = await run('exit 3');

    expect(code, 3);
  });

  test('убитая сигналом успешной не выглядит', () async {
    final (_, code) = await run('kill -TERM \$\$');

    // Как в `dart:io`: сигнал — отрицательное число, а не ноль.
    expect(code, -15);
  });

  test('это настоящий терминал, а не пара труб', () async {
    final (text, code) = await run('test -t 0 && echo терминал');

    expect(text, contains('терминал'));
    expect(code, 0);
  });

  test('у программы есть управляющий терминал', () async {
    // `/dev/tty` — это он и есть. Без `POSIX_SPAWN_SETSID` и открытия ведомой
    // стороны в потомке здесь была бы ошибка, а `vim`, `htop` и `Ctrl-C`
    // работали бы неправильно.
    final (text, code) = await run('echo есть > /dev/tty');

    expect(text, contains('есть'));
    expect(code, 0);
  });

  test('размер окна программа видит тот, что задали', () async {
    final (text, _) = await run('stty size', columns: 100, rows: 30);

    expect(text, contains('30 100'));
  });

  test('рабочий каталог — тот, что просили', () async {
    final (text, code) = await run('pwd', directory: '/tmp');

    expect(text, contains('/tmp'));
    expect(code, 0);
  });

  test('несуществующая программа объясняется словами', () {
    expect(
      () => const SystemPtyLauncher().start(executable: '/no/such/program', environment: const {}),
      throwsA(isA<PtyError>().having((error) => error.message, 'message', contains('not found'))),
    );
  });

  test('окружение наследуется, и оболочка понимает UTF-8', () async {
    // Ошибка, ради которой этот тест и написан: с пустым окружением оболочка
    // без `LANG` считает UTF-8 побайтно, и `Backspace` стирает половину
    // двухбайтового символа — на экране остаётся мусор. Проверяется настоящей
    // оболочкой: подставке такое не изобразить.
    final session = const SystemPtyLauncher().start(
      executable: '/bin/sh',
      arguments: const ['-c', 'printf "%s %s %s" "\$TERM" "\${LANG:-\${LC_ALL:-none}}" "\${HOME:-none}"'],
      environment: const {},
    );

    final output = StringBuffer();
    session.output.listen((chunk) => output.write(utf8.decode(chunk, allowMalformed: true)));
    await session.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final line = output.toString().trim().split(RegExp(r'\s+'));
    expect(line[0], 'xterm-256color', reason: 'без TERM программа считает терминал дурным');
    expect(line[1].toUpperCase(), contains('UTF-8'), reason: 'без UTF-8 локали ломается кириллица');
    expect(line[2], isNot('none'), reason: 'без HOME не читаются настройки');
  });

  test('своё в окружении важнее унаследованного', () async {
    final (text, _) = await run(r'echo "$TERM"');
    expect(text, contains('dumb'), reason: 'заданное вызывающим не должно теряться');
  });

  test('молчащая программа изолят чтения не запирает', () async {
    // Ожидание ограничено по времени нарочно: изолят, висящий в системном
    // вызове, до точки останова не доходит — его нельзя ни остановить, ни
    // разобрать вместе с группой, и на этом спотыкается перезапуск приложения.
    final session = const SystemPtyLauncher().start(
      executable: '/bin/sh',
      arguments: const ['-c', 'sleep 5'],
      environment: const {},
    );

    // Программа молчит всё это время, а чтение обязано пережить молчание и
    // остаться живым: следом за паузой она скажет своё слово.
    await Future<void>.delayed(Duration(milliseconds: PtyReader.waitMs * 3));
    session.write(utf8.encode(''));

    final output = StringBuffer();
    session.output.listen((chunk) => output.write(utf8.decode(chunk, allowMalformed: true)));
    await session.kill();

    expect(await session.exitCode, isNot(0), reason: 'убитая программа успешной не выглядит');
  });

  test('ввод доходит до программы', () async {
    final session = const SystemPtyLauncher().start(
      executable: '/bin/sh',
      arguments: const ['-c', 'read line; echo "принято: \$line"'],
      environment: const {'TERM': 'dumb'},
    );

    final output = StringBuffer();
    session.output.listen((chunk) => output.write(utf8.decode(chunk, allowMalformed: true)));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    session.write(utf8.encode('строка\n'));

    final code = await session.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(output.toString(), contains('принято: строка'));
    expect(code, 0);
  });
}
