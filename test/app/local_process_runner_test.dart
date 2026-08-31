import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:flutter_test/flutter_test.dart';

/// Запуск программ — единственное место, где проверять подставку бессмысленно:
/// вся суть здесь в том, как ведёт себя настоящий процесс. Команды взяты
/// переносимые (`sh`, `printf`), чтобы тест не зависел от того, что стоит на
/// машине.
void main() {
  const runner = LocalProcessRunner();

  test('вывод и код возврата', () async {
    final outcome = await runner.run('sh', ['-c', 'printf hello; printf oops >&2; exit 3']);

    expect(outcome.exitCode, 3);
    expect(outcome.ok, isFalse);
    expect(outcome.stdout, 'hello');
    expect(outcome.stderr, 'oops');
  });

  test('рабочий каталог', () async {
    final directory = Directory.systemTemp.createTempSync('fc_process_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/marker.txt').writeAsStringSync('here');

    final outcome = await runner.run('sh', ['-c', 'cat marker.txt'], workingDirectory: directory.path);

    expect(outcome.stdout, 'here');
  });

  test('вывод длиннее буфера канала не подвешивает работу', () async {
    // Тупик на неразобранном втором канале проявляется только на выводе,
    // который не помещается в буфер: короткий тест его не поймал бы.
    final outcome = await runner.run('sh', ['-c', r"head -c 200000 /dev/zero | tr '\0' 'x'; echo done >&2"]);

    expect(outcome.stdout.length, 200000);
    expect(outcome.stderr.trim(), 'done');
  });

  test('ввод закрыт: программа, читающая stdin, не ждёт вечно', () async {
    // Без закрытого ввода `cat` не увидит конца потока и не завершится —
    // именно так подвисает 7z на архиве с паролем.
    final outcome = await runner.run('cat', []).timeout(const Duration(seconds: 5));

    expect(outcome.exitCode, 0);
    expect(outcome.stdout, isEmpty);
  });

  test('поток отдаётся по мере поступления', () async {
    final session = await runner.start('sh', ['-c', 'printf one; printf two']);
    final text = await session.stdout.transform(utf8.decoder).join();

    expect(text, 'onetwo');
    expect(await session.exitCode, 0);
  });

  test('kill прерывает работу', () async {
    final session = await runner.start('sh', ['-c', 'sleep 30']);
    await session.kill();

    expect(await session.exitCode.timeout(const Duration(seconds: 5)), isNot(0));
  });

  test('несуществующая программа — понятная ошибка, а не крах', () async {
    await expectLater(
      runner.run('fc_definitely_not_a_program', []),
      throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.notFound)),
    );
  });

  group('поиск программы', () {
    test('находит по PATH', () async {
      final found = await runner.which('sh');

      expect(found, isNotNull);
      expect(File(found!).existsSync(), isTrue);
    });

    test('не находит того, чего нет', () async {
      expect(await runner.which('fc_definitely_not_a_program'), isNull);
    });

    test('смотрит и в указанные каталоги: PATH приложения из Finder куцый', () async {
      final directory = Directory.systemTemp.createTempSync('fc_process_which');
      addTearDown(() => directory.deleteSync(recursive: true));

      final program = File('${directory.path}/fc_fake_tool')..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', ['+x', program.path]);

      expect(await runner.which('fc_fake_tool'), isNull);
      expect(await runner.which('fc_fake_tool', extraDirectories: [directory.path]), program.path);
    });

    test('файл без бита выполнения программой не считается', () async {
      final directory = Directory.systemTemp.createTempSync('fc_process_which');
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}/fc_data_file').writeAsStringSync('не программа');

      expect(await runner.which('fc_data_file', extraDirectories: [directory.path]), isNull);
    });

    test('путь вместо имени проверяется как есть', () async {
      expect(await runner.which('/bin/sh'), '/bin/sh');
      expect(await runner.which('/bin/fc_definitely_not_a_program'), isNull);
    });
  });
}
