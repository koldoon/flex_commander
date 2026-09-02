import 'dart:convert';
import 'dart:io';

import 'package:fc_7z/fc_7z.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Архив под паролем: кто спрашивает, что запоминается и что бывает при отказе.
void main() {
  late Directory temp;
  late File archive;
  late LocalTreeProvider local;

  const listing = '''
----------
Path = secret.txt
Size = 12
Attributes = A_ -rw-r--r--
Encrypted = +
''';

  /// Ответ программы на архив, оглавление которого зашифровано.
  const lockedHeaders = FakeProcessReply(
    exitCode: 2,
    stderr: 'ERROR: sample.7z : Cannot open encrypted archive. Wrong password?',
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fc_7z_password');
    archive = File('${temp.path}/sample.7z')..writeAsStringSync('архив');
    local = LocalTreeProvider();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<TreeProvider> open(FakeProcessRunner runner, FakeCredentials credentials) async {
    final host = (await local.resolvePath().run(archive.path))!;
    final provider = await SevenZipTreeProvider.open(
      host,
      staging: LocalStagingArea(root: temp),
      cli: SevenZipCli(processes: runner),
      credentials: credentials,
    );
    addTearDown(() => (provider as ProviderLifecycle).dispose());
    return provider;
  }

  /// Программа, открывающая архив только этим паролем.
  FakeProcessRunner runnerLockedWith(String password) {
    return FakeProcessRunner(
      reply: (call) {
        final given = call.arguments.firstWhere((argument) => argument.startsWith('-p'), orElse: () => '-p');
        if (given != '-p$password') {
          return lockedHeaders;
        }
        return call.command == 'l'
            ? const FakeProcessReply(stdout: listing)
            : FakeProcessReply(stdoutChunks: [utf8.encode('содержимое')]);
      },
    );
  }

  group('шифрованное оглавление', () {
    test('пароль спрашивается и подставляется программе', () async {
      final runner = runnerLockedWith('тайна');
      final credentials = FakeCredentials(answers: ['тайна']);

      final provider = await open(runner, credentials);

      expect(credentials.asked, hasLength(1));
      expect(credentials.asked.single.title, 'Encrypted archive');
      expect(credentials.asked.single.retry, isFalse);
      expect(runner.callsOf('l').last.arguments, contains('-pтайна'));
      expect(await provider.listChildren(provider.rootDirectory), isNotEmpty);
    });

    test('неверный пароль — второй вопрос, уже с пометкой', () async {
      final runner = runnerLockedWith('тайна');
      final credentials = FakeCredentials(answers: ['мимо', 'тайна']);

      await open(runner, credentials);

      expect(credentials.asked, hasLength(2));
      expect(credentials.asked.last.retry, isTrue, reason: 'окно должно сказать, что прошлый не подошёл');
      // Не подошедший забыт: иначе второй вопрос вернул бы тот же ответ.
      expect(credentials.known[credentials.asked.first.realm]?.password, 'тайна');
    });

    test('отказ пользователя — отказ в доступе, а не пустой архив', () async {
      final runner = runnerLockedWith('тайна');
      final credentials = FakeCredentials();

      final host = (await local.resolvePath().run(archive.path))!;
      await expectLater(
        SevenZipTreeProvider.open(
          host,
          staging: LocalStagingArea(root: temp),
          cli: SevenZipCli(processes: runner),
          credentials: credentials,
        ),
        throwsA(isA<FsError>().having((e) => e.kind, 'kind', FsErrorKind.permissionDenied)),
      );
    });
  });

  group('шифрованная запись', () {
    test('пароль спрашивается один раз на архив, а не на файл', () async {
      // Оглавление читается без пароля, а записи зашифрованы поодиночке.
      final runner = FakeProcessRunner(
        reply:
            (call) =>
                call.command == 'l'
                    ? const FakeProcessReply(stdout: listing)
                    : FakeProcessReply(stdoutChunks: [utf8.encode('содержимое')]),
      );
      final credentials = FakeCredentials(answers: ['тайна']);

      final provider = await open(runner, credentials);
      final node = (await provider.resolvePath().run('/secret.txt'))!;

      for (var attempt = 0; attempt < 3; attempt++) {
        final bytes = await (provider as FileContentProvider).openRead(node);
        expect(utf8.decode(await bytes.expand((chunk) => chunk).toList()), 'содержимое');
      }

      // Программа запускается на каждое чтение — вопрос не должен.
      expect(credentials.asked, hasLength(1));
      expect(runner.callsOf('x').every((call) => call.arguments.contains('-pтайна')), isTrue);
    });

    test('не подошедший пароль забывается, и следующее чтение спрашивает снова', () async {
      var attempts = 0;
      final runner = FakeProcessRunner(
        reply: (call) {
          if (call.command == 'l') {
            return const FakeProcessReply(stdout: listing);
          }
          attempts++;
          // Первый пароль не подходит, второй подходит.
          return attempts == 1
              ? const FakeProcessReply(exitCode: 2, stderr: 'ERROR: Wrong password?')
              : FakeProcessReply(stdoutChunks: [utf8.encode('содержимое')]);
        },
      );
      final credentials = FakeCredentials(answers: ['мимо', 'тайна']);

      final provider = await open(runner, credentials);
      final node = (await provider.resolvePath().run('/secret.txt'))!;

      final failing = await (provider as FileContentProvider).openRead(node);
      await expectLater(failing.drain<void>(), throwsA(isA<FsError>()));

      final bytes = await (provider as FileContentProvider).openRead(node);
      expect(utf8.decode(await bytes.expand((chunk) => chunk).toList()), 'содержимое');
      expect(credentials.asked, hasLength(2));
    });
  });
}
