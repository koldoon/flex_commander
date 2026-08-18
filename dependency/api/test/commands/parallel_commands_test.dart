import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_commands.dart';

void main() {
  late List<String> log;

  setUp(() => log = []);

  test('шаги идут одновременно, а не по очереди', () async {
    await Commands.inParallel()
        .add(LoggingCommand('slow', log, delay: const Duration(milliseconds: 20)))
        .add(LoggingCommand('fast', log))
        .execute();

    // Оба начались до того, как закончился первый.
    expect(log.take(2), ['slow:start', 'fast:start']);
    expect(log.last, 'slow:done');
  });

  test('группа ждёт всех, даже если один упал', () async {
    late List<CommandResult> results;

    await expectLater(
      Commands.inParallel()
          .add(FailingCommand('нет доступа'))
          .add(LoggingCommand('other', log, delay: const Duration(milliseconds: 10)))
          .allResults((all) => results = all)
          .execute(),
      throwsA(isA<CommandFailure>()),
    );

    // Прерывать уже начатую работу на полпути незачем: она доводится до конца,
    // и её итог виден в отчёте.
    expect(log, ['other:start', 'other:done']);
    expect(results, hasLength(2));
  });

  test('со skipErrors падение одного не роняет группу', () async {
    late List<CommandResult> results;

    await Commands.inParallel()
        .skipErrors()
        .add(FailingCommand('нет доступа'))
        .add(LoggingCommand('other', log))
        .allResults((all) => results = all)
        .execute();

    expect(results.where((r) => r.complete), hasLength(1));
    expect(results.where((r) => r.error != null), hasLength(1));
  });

  test('отмена группы прерывает всё, что работает', () async {
    final first = BlockingCommand('first');
    final second = BlockingCommand('second');
    final group = Commands.inParallel().add(first).add(second).build();

    final run = group.execute();
    await Future<void>.delayed(Duration.zero);

    group.cancel();

    await expectLater(run, throwsA(isA<CommandCanceled>()));
    expect(first.canceled, isTrue);
    expect(second.canceled, isTrue);
  });

  test('результаты всех шагов попадают в данные группы', () async {
    late List<CommandResult> results;

    await Commands.inParallel()
        .add(ValueCommand<String>('/home'))
        .add(ValueCommand<int>(42))
        .allResults((all) => results = all)
        .execute();

    expect(results.map((r) => r.value), containsAll(<Object>['/home', 42]));
  });
}
