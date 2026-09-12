import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_updater/fc_updater.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подмена приложения собой же (`docs/spec/self-update.md`, §6).
void main() {
  late Directory workspace;
  late FakeProcessRunner processes;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('fc_install');
    processes = FakeProcessRunner();
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  UpdateInstall install() => UpdateInstall(processes: processes, workspace: workspace);

  /// Подставной `ditto`: кладёт в назначенный каталог то, что ему велели.
  FakeProcessRunner unpacking(List<String> bundles) => FakeProcessRunner(
    reply: (call) {
      if (call.executable.endsWith('ditto')) {
        final into = call.arguments.last;
        for (final name in bundles) {
          Directory('$into/$name').createSync(recursive: true);
        }
      }
      return const FakeProcessReply();
    },
  );

  test('распаковка зовёт системный ditto и отдаёт найденный бандл', () async {
    processes = unpacking(['flex_commander.app']);
    final archive = File('${workspace.path}/release.zip')..writeAsStringSync('не важно');

    final bundle = await install().unpack(archive);

    expect(bundle.path, endsWith('flex_commander.app'));
    expect(processes.lastCall.executable, '/usr/bin/ditto');
    expect(processes.lastCall.arguments.take(3), ['-x', '-k', archive.path]);
  });

  test('в архиве не одно приложение — гадать на месте подмены нельзя', () async {
    final archive = File('${workspace.path}/release.zip')..writeAsStringSync('не важно');

    processes = unpacking(const []);
    await expectLater(install().unpack(archive), throwsA(isA<FsError>()), reason: 'пусто');

    processes = unpacking(['one.app', 'two.app']);
    await expectLater(install().unpack(archive), throwsA(isA<FsError>()), reason: 'два бандла');
  });

  test('ditto отказал — это не подмена, а отказ', () async {
    processes = FakeProcessRunner(reply: (_) => const FakeProcessReply(exitCode: 1));
    final archive = File('${workspace.path}/release.zip')..writeAsStringSync('не важно');

    await expectLater(install().unpack(archive), throwsA(isA<FsError>()));
  });

  test('помощник запускается отпущенным и получает пути аргументами', () async {
    final replacement = Directory('${workspace.path}/new/flex_commander.app')..createSync(recursive: true);

    await install().handOver(replacement: replacement, target: '/Applications/flex commander.app', pid: 4242);

    final call = processes.detached.single;
    expect(call.executable, '/bin/sh');
    expect(call.arguments.first, '-c');
    expect(call.arguments.sublist(2), [
      'fc-update',
      '4242',
      replacement.path,
      '/Applications/flex commander.app',
      '/Applications/flex commander.app.previous',
    ], reason: 'пути уходят аргументами: в них бывают пробелы');
  });

  test('отложенную сборку убирает следующий запуск', () async {
    final bundle = Directory('${workspace.path}/flex_commander.app')..createSync();
    final backup = Directory('${bundle.path}${UpdateInstall.backupSuffix}')..createSync();

    await UpdateInstall.forgetBackup(bundle.path);

    expect(backup.existsSync(), isFalse);
    expect(bundle.existsSync(), isTrue, reason: 'убирают прежнюю, а не нынешнюю');
  });

  group('сам помощник', () {
    /// Тот же сценарий, что уходит в `/bin/sh`, — и на настоящих каталогах.
    ///
    /// Проверять его подставкой бессмысленно: вся его суть в том, что делает
    /// оболочка. Приложение здесь изображает `sleep`, которому дают закончиться.
    Future<ProcessOutcome> runHelper({required String target, required String replacement, required int pid}) async {
      final script = UpdateInstall(processes: const LocalProcessRunner(), workspace: workspace).helperScript;
      return const LocalProcessRunner().run('/bin/sh', [
        '-c',
        script,
        'fc-update',
        '$pid',
        replacement,
        target,
        '$target${UpdateInstall.backupSuffix}',
      ]);
    }

    test('подменяет каталог и откладывает прежний', () async {
      final target = Directory('${workspace.path}/flex commander.app')..createSync();
      File('${target.path}/mark').writeAsStringSync('старая');
      final replacement = Directory('${workspace.path}/new/flex commander.app')..createSync(recursive: true);
      File('${replacement.path}/mark').writeAsStringSync('новая');

      // `pid` заведомо мёртвого процесса: ждать нам некого.
      final outcome = await runHelper(target: target.path, replacement: replacement.path, pid: 999999);

      expect(outcome.ok, isTrue, reason: outcome.stderr);
      expect(File('${target.path}/mark').readAsStringSync(), 'новая');
      expect(
        File('${target.path}${UpdateInstall.backupSuffix}/mark').readAsStringSync(),
        'старая',
        reason: 'прежняя сборка остаётся рядом — если новая не запустится',
      );
    });
  });
}
