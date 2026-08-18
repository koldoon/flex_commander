import 'package:fc_api/fc_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Клавиши файловых операций и то, что они умеют рассказать о себе.
void main() {
  late CommandService commands;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1)]),
      modules: [const FileOps()],
    );
    commands = runtime.commands;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('операции закреплены за F-клавишами', () {
    expect(commands.commandFor(KeyCombination.parse('F5'))?.id, 'file.copy');
    expect(commands.commandFor(KeyCombination.parse('F6'))?.id, 'file.move');
    expect(commands.commandFor(KeyCombination.parse('F7'))?.id, 'file.mkdir');
    expect(commands.commandFor(KeyCombination.parse('F8'))?.id, 'file.remove');
  });

  test('у macOS есть свои сочетания', () {
    // F-клавиши там по умолчанию отданы системе, и до окна нажатие не доходит.
    expect(commands.commandFor(KeyCombination.parse('Shift-Cmd-N'))?.id, 'file.mkdir');
    expect(commands.commandFor(KeyCombination.parse('Cmd-Bsp'))?.id, 'file.remove');
    expect(commands.commandFor(KeyCombination.parse('Shift-Cmd-Bsp'))?.id, 'file.removePermanently');
  });

  test('длительные операции рассказывают о ходе работы', () {
    // Из этого и растёт фоновое выполнение: ядро прячет окно, а ход дела
    // показывает рядом с остальными такими же.
    for (final id in ['file.remove', 'file.removePermanently', 'file.copy', 'file.move']) {
      expect(commands.find(id), isA<TaskStatus>(), reason: 'команда $id не умеет рассказать о себе');
      expect(commands.find(id)!.canRunInBackground, isTrue);
    }
  });

  test('приложение собирается и без файловых операций', () async {
    final runtime = await testApp(provider: InMemoryTreeProvider([FakeEntry.directory('/home')]));

    expect(runtime.commands.find('file.copy'), isNull);
    expect(runtime.app.left, isNotNull);
  });
}
