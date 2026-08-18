import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_commands.dart';

void main() {
  late List<String> log;

  setUp(() => log = []);

  test('шаги идут один за другим, а не вперемешку', () async {
    await Commands.asSequence()
        .add(LoggingCommand('first', log, delay: const Duration(milliseconds: 10)))
        .add(LoggingCommand('second', log))
        .execute();

    expect(log, ['first:start', 'first:done', 'second:start', 'second:done']);
  });

  test('следующий шаг достаёт результат предыдущего из данных', () async {
    ConsumingCommand<String>? consumer;

    await Commands.asSequence()
        .add(ValueCommand<String>('/home/docs'))
        .create((data) => consumer = ConsumingCommand<String>(data))
        .execute();

    expect(consumer?.taken, '/home/docs');
  });

  test('ошибка шага останавливает всю последовательность', () async {
    await expectLater(
      Commands.asSequence()
          .add(LoggingCommand('first', log))
          .add(FailingCommand('нет доступа'))
          .add(LoggingCommand('third', log))
          .execute(),
      throwsA(isA<CommandFailure>().having((f) => f.cause, 'причина', 'нет доступа')),
    );

    expect(log, ['first:start', 'first:done']);
  });

  test('со skipErrors работа продолжается, а итог шага остаётся в отчёте', () async {
    late List<CommandResult> results;

    await Commands.asSequence()
        .skipErrors()
        .add(FailingCommand('нет доступа'))
        .add(LoggingCommand('second', log))
        .allResults((all) => results = all)
        .execute();

    expect(log, ['second:start', 'second:done']);
    expect(results.first.complete, isFalse);
    expect(results.first.error, 'нет доступа');
    expect(results.last.complete, isTrue);
  });

  test('отмена шага отменяет последовательность', () async {
    await expectLater(
      Commands.asSequence().add(SelfCancelingCommand()).add(LoggingCommand('second', log)).execute(),
      throwsA(isA<CommandCanceled>()),
    );

    expect(log, isEmpty);
  });

  test('со skipCancellations отменённый шаг только пропускается', () async {
    await Commands.asSequence()
        .skipCancellations()
        .add(SelfCancelingCommand())
        .add(LoggingCommand('second', log))
        .execute();

    expect(log, ['second:start', 'second:done']);
  });

  test('отмена группы прерывает текущий шаг и не пускает следующий', () async {
    final blocking = BlockingCommand();
    final sequence = Commands.asSequence().add(blocking).add(LoggingCommand('second', log)).build();

    final run = sequence.execute();
    await Future<void>.delayed(Duration.zero);
    expect(blocking.started, isTrue);

    sequence.cancel();

    await expectLater(run, throwsA(isA<CommandCanceled>()));
    expect(blocking.canceled, isTrue);
    expect(log, isEmpty);
  });

  test('пауза останавливает работу между шагами', () async {
    final sequence = Commands.asSequence().add(LoggingCommand('first', log)).add(LoggingCommand('second', log)).build();

    sequence.suspend();
    final run = sequence.execute();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Первый шаг уже не начнётся: пауза разбирается перед каждым шагом.
    expect(log, isEmpty);
    expect(sequence.suspended, isTrue);

    sequence.resume();
    await run;
    expect(log, ['first:start', 'first:done', 'second:start', 'second:done']);
  });

  test('обработчик ошибки берёт её на себя', () async {
    Object? handled;

    await Commands.asSequence().add(FailingCommand('нет доступа')).error((error) => handled = error).execute();

    expect(handled, isA<CommandFailure>());
  });

  group('данные наружу', () {
    test('результат шага, созданного при запуске, виден следующему шагу', () async {
      ConsumingCommand<String>? consumer;

      // `create` заворачивает шаг в обёртку, и без передачи данных наверх
      // следующий шаг не увидел бы ничего: сборка приложения именно так и
      // разваливалась.
      await Commands.asSequence()
          .create((data) => ValueCommand<String>('/home/docs'))
          .create((data) => consumer = ConsumingCommand<String>(data))
          .execute();

      expect(consumer?.taken, '/home/docs');
    });

    test('данные вложенной группы доходят до внешней', () async {
      final inner = Commands.asSequence().add(ValueCommand<String>('/home')).build();
      final outer = Commands.asSequence().add(inner).build();

      await outer.execute();

      expect(outer.result?.getObject<String>(), '/home');
    });

    test('замкнутая цепочка данных не уводит поиск в бесконечность', () async {
      final group = Commands.asSequence().add(ValueCommand<int>(42)).build();
      await group.execute();

      final data = group.result!;
      // Данные группы лежат в них же самих: она отдаёт их наружу, а наружу —
      // это и есть её родитель. Поиск обязан на этом закончиться.
      data.add(data);

      expect(data.getObject<int>(), 42);
      expect(data.getObject<String>(), isNull);
      expect(data.getAllObjects<int>(), [42]);
    });
  });
}
