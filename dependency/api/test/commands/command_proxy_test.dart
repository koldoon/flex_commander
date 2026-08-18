import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_commands.dart';

void main() {
  late List<String> log;

  setUp(() => log = []);

  test('обёртка выполняет команду и отдаёт результат', () async {
    Object? value;

    await Commands.wrap(ValueCommand<String>('/home')).result((result) => value = result).execute();

    expect(value, '/home');
  });

  test('без обработчика ошибка уходит наружу', () async {
    await expectLater(
      Commands.wrap(FailingCommand('нет доступа')).execute(),
      throwsA(isA<CommandFailure>().having((f) => f.cause, 'причина', 'нет доступа')),
    );
  });

  test('с обработчиком ошибка считается разобранной', () async {
    Object? handled;

    await Commands.wrap(FailingCommand('нет доступа')).error((error) => handled = error).execute();

    expect(handled, 'нет доступа');
  });

  test('обычная функция тоже команда', () async {
    await Commands.of(() async => log.add('сделано')).execute();

    expect(log, ['сделано']);
  });

  test('срок прерывает ожидание и саму работу, если её есть чем прервать', () async {
    final blocking = BlockingCommand();

    await expectLater(
      Commands.wrap(blocking).timeout(const Duration(milliseconds: 10)).execute(),
      throwsA(isA<CommandFailure>().having((f) => f.cause, 'причина', isA<CommandTimeout>())),
    );

    expect(blocking.canceled, isTrue);
  });

  test('уложившаяся в срок работа не прерывается', () async {
    await Commands.of(() async => log.add('быстро')).timeout(const Duration(seconds: 5)).execute();

    expect(log, ['быстро']);
  });

  test('отмена обёртки прерывает команду', () async {
    final blocking = BlockingCommand();
    final proxy = Commands.wrap(blocking).build();

    final run = proxy.execute();
    await Future<void>.delayed(Duration.zero);
    proxy.cancel();

    await expectLater(run, throwsA(isA<CommandCanceled>()));
    expect(blocking.canceled, isTrue);
  });

  test('пауза передаётся вложенной группе', () async {
    final inner = Commands.asSequence().add(LoggingCommand('inner', log)).build();
    final outer = Commands.asSequence().add(inner).build();

    outer.suspend();
    final run = outer.execute();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(log, isEmpty);

    outer.resume();
    await run;
    expect(log, ['inner:start', 'inner:done']);
  });

  test('вложенные падения раскручиваются до исходной причины', () async {
    final inner = Commands.asSequence().add(FailingCommand('нет доступа')).build();

    try {
      await Commands.asSequence().add(inner).execute();
      fail('ожидалось падение');
    } on CommandFailure catch (failure) {
      expect(failure.cause, isA<CommandFailure>());
      expect(failure.rootCause, 'нет доступа');
    }
  });
}
