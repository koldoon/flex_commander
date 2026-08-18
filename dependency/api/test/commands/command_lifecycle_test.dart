import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_commands.dart';

void main() {
  test('команда создаётся окружением, а не фабрикой напрямую', () async {
    final lifecycle = RecordingLifecycle(<String>[]);

    await Commands.create((data) => ValueCommand<String>('/home')).lifecycle(lifecycle).execute();

    expect(lifecycle.created, 1);
    expect(lifecycle.log.first, 'create');
  });

  test('окружение зовут до и после каждого шага', () async {
    final lifecycle = RecordingLifecycle(<String>[]);
    final log = <String>[];

    await Commands.asSequence()
        .add(LoggingCommand('first', log))
        .add(LoggingCommand('second', log))
        .lifecycle(lifecycle)
        .execute();

    expect(lifecycle.log, ['before:first', 'after:first:true', 'before:second', 'after:second:true']);
  });

  test('после упавшего шага окружение тоже зовут', () async {
    final lifecycle = RecordingLifecycle(<String>[]);

    await expectLater(
      Commands.asSequence().add(FailingCommand()).lifecycle(lifecycle).execute(),
      throwsA(isA<CommandFailure>()),
    );

    expect(lifecycle.log, ['before:FailingCommand', 'after:FailingCommand:false']);
  });

  test('окружение достаётся вложенным группам', () async {
    final lifecycle = RecordingLifecycle(<String>[]);
    final log = <String>[];
    final inner = Commands.asSequence().add(LoggingCommand('inner', log)).build();

    await Commands.asSequence().add(inner).lifecycle(lifecycle).execute();

    // Вложенная группа не создаёт своё окружение: она получает родительское.
    expect(lifecycle.log, contains('before:inner'));
  });

  test('данные, заданные построителю, видны команде', () async {
    ConsumingCommand<String>? consumer;

    await Commands.asSequence().data('/home').create((data) => consumer = ConsumingCommand<String>(data)).execute();

    expect(consumer?.taken, '/home');
  });
}
