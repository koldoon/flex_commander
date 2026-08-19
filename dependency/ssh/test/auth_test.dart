import 'dart:io';

import 'package:fc_ssh/fc_ssh.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Ключи-заготовки: сделаны для этого теста и больше нигде не используются.
/// Проверяется на них не криптография, а порядок вопросов — и то, что вопрос
/// задаётся ровно там, где без него не обойтись.
const String plainKey = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACAvSGcxXiE89NxZat+4jdgp7OoBxXRVbyGkdwS81mz3FwAAAKgDod1iA6Hd
YgAAAAtzc2gtZWQyNTUxOQAAACAvSGcxXiE89NxZat+4jdgp7OoBxXRVbyGkdwS81mz3Fw
AAAECiuM3S3Pp9uURq+mB7ShzL0mqQIsaRn1OkLOSloR7bGC9IZzFeITz03Flq37iN2Cns
6gHFdFVvIaR3BLzWbPcXAAAAH2ZsZXgtY29tbWFuZGVyIHRlc3Qga2V5IChwbGFpbikBAg
MEBQY=
-----END OPENSSH PRIVATE KEY-----
''';

/// Тот же формат, но под парольной фразой «phrase».
const String lockedKey = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBD38KpIF
LXGky1T3DGAtmMAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAINVxVq0JXmc+eRpv
4PbfYLu0aehyL1mwyy74wfWRV4ETAAAAsNKi/N+T2hTYemqPIq5IYF7T9lBhGKIjn8aOFq
ZK3GfCtcD25vq1hnHKeoxKQCx2F57KqSvZSX1V1/wQllwwd6JfUfVYKG5L/Qq1zBWJIVQg
8gSz1ZN3cjzqvTRHhyKSWFsdRmP0UHnQ5Ytc8WFnYr6G5jOjjPIA97INsxoRNgPB7kZ09V
tmlwYidj0rG06ZBbS2v6YcJNkV81Af6ftSCvkPwlE2BLs30DGACFAUp0d0
-----END OPENSSH PRIVATE KEY-----
''';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_ssh_keys');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<void> put(String name, String pem) => File(p.join(temp.path, name)).writeAsString('$pem\n');

  group('связка ключей', () {
    test('пустого каталога достаточно: остаётся пароль', () async {
      final keyring = await SshKeyring.read(p.join(temp.path, 'нет-такого'));

      expect(keyring.isEmpty, isTrue);
      expect(keyring.ready, isEmpty);
      expect(keyring.locked, isEmpty);
    });

    test('ключ без фразы открывается молча', () async {
      await put('id_ed25519', plainKey);

      final keyring = await SshKeyring.read(temp.path);

      expect(keyring.ready, hasLength(1));
      expect(keyring.locked, isEmpty);
    });

    test('ключ под фразой откладывается до вопроса', () async {
      await put('id_ed25519', lockedKey);

      final keyring = await SshKeyring.read(temp.path);

      expect(keyring.ready, isEmpty);
      expect(keyring.locked, hasLength(1));
      expect(keyring.locked.single, endsWith('id_ed25519'));
    });

    test('мусор вместо ключа не мешает остальным', () async {
      await put('id_ed25519', 'это не ключ');
      await put('id_rsa', plainKey);

      final keyring = await SshKeyring.read(temp.path);

      expect(keyring.ready, hasLength(1));
    });

    test('чужие файлы в каталоге не трогаются', () async {
      await put('id_ed25519.pub', plainKey);
      await put('known_hosts', plainKey);

      expect((await SshKeyring.read(temp.path)).isEmpty, isTrue);
    });
  });

  group('парольная фраза', () {
    test('спрашивается один раз и открывает ключ', () async {
      await put('id_ed25519', lockedKey);
      final keyring = await SshKeyring.read(temp.path);
      final credentials = FakeCredentials(answers: ['phrase']);

      final unlocked = await keyring.unlock(credentials);

      expect(unlocked, hasLength(1));
      expect(credentials.asked, hasLength(1));
      expect(credentials.asked.single.realm, startsWith('ssh-key:'));
      expect(credentials.asked.single.realm, endsWith('id_ed25519'));
      expect(credentials.asked.single.retry, isFalse);
    });

    test('не подошла — спрашивается заново, и об этом сказано', () async {
      await put('id_ed25519', lockedKey);
      final keyring = await SshKeyring.read(temp.path);
      final credentials = FakeCredentials(answers: ['не та', 'phrase']);

      final unlocked = await keyring.unlock(credentials);

      expect(unlocked, hasLength(1));
      expect(credentials.asked, hasLength(2));
      expect(credentials.asked.last.retry, isTrue);
    });

    test('отказ отвечать — ключ просто не открылся', () async {
      await put('id_ed25519', lockedKey);
      final keyring = await SshKeyring.read(temp.path);
      final credentials = FakeCredentials();

      expect(await keyring.unlock(credentials), isEmpty);
      expect(credentials.asked, hasLength(1));
    });

    test('трижды мимо — больше не спрашиваем', () async {
      await put('id_ed25519', lockedKey);
      final keyring = await SshKeyring.read(temp.path);
      final credentials = FakeCredentials(answers: ['раз', 'два', 'три', 'phrase']);

      expect(await keyring.unlock(credentials), isEmpty);
      expect(credentials.asked, hasLength(3));
    });

    test('за ключ без фразы никого не спрашивают', () async {
      await put('id_ed25519', plainKey);
      final keyring = await SshKeyring.read(temp.path);
      final credentials = FakeCredentials(answers: ['phrase']);

      expect(await keyring.unlock(credentials), isEmpty);
      expect(credentials.asked, isEmpty);
    });
  });

  group('область запоминания', () {
    test('у ключа — сам ключ, а не сервер: он ходит на многие', () async {
      await put('id_ed25519', lockedKey);
      final keyring = await SshKeyring.read(temp.path);
      final credentials = FakeCredentials(answers: ['phrase']);

      await keyring.unlock(credentials);
      await keyring.unlock(credentials);

      // Второй раз фразу уже помнят.
      expect(credentials.asked, hasLength(1));
    });
  });
}
