import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sftp.dart';

/// Атрибуты на той стороне: что можно поменять по SFTP, а чего нельзя.
///
/// Главное здесь — не сами вызовы, а **пары**: в третьей версии протокола даты
/// и числа владельца лежат под одним признаком, один на двоих, и половина пары
/// не выразима. Отсюда и умения, выведенные из того, что прислал сервер, и
/// дочитывание недостающей половины.
void main() {
  late FakeSftp server;
  late SftpTreeProvider provider;

  setUp(() {
    server = FakeSftp();
    server.directory('/srv');
    server.file(
      '/srv/notes.txt',
      'заметки',
      mode: 0x81A4, // -rw-r--r--
      uid: 1000,
      gid: 1000,
      modified: DateTime.utc(2020, 1, 2, 3, 4, 5),
      accessed: DateTime.utc(2020, 1, 2, 3, 4, 6),
    );
    // Сервер, который прислал только режим: так отвечают самые скупые.
    server.file('/srv/bare.txt', 'скупо', mode: 0x81A4);
    server.link('/srv/current', '/srv/notes.txt');

    provider = SftpTreeProvider(
      target: SshTarget.parse(Uri.parse('ssh://tester@example.org/')),
      sftp: server,
      homePath: server.home,
    );
  });

  Future<FsNode> node(String path) async => (await provider.resolvePath().run(path))!;

  test('читает то, что прислал сервер', () async {
    final attributes = await provider.readAttributes(await node('/srv/notes.txt'));

    expect(attributes.modeString, '-rw-r--r--');
    expect(attributes.permissions, 0x1A4);
    expect(attributes.uid, 1000);
    expect(attributes.gid, 1000);
    expect(attributes.modified, DateTime.utc(2020, 1, 2, 3, 4, 5));
  });

  test('имён владельца не обещает: сервер их не знает', () async {
    final attributes = await provider.readAttributes(await node('/srv/notes.txt'));

    // Словаря пользователей чужой машины у нас нет, и владелец там остаётся
    // числом. Врать про имя хуже, чем показать число.
    expect(attributes.owner, isEmpty);
    expect(attributes.group, isEmpty);
  });

  test('расширенных атрибутов на сервере нет вовсе', () async {
    final attributes = await provider.readAttributes(await node('/srv/notes.txt'));

    // Не «мы не умеем», а «в третьей версии протокола их не существует».
    expect(provider, isNot(isA<NodeXattrEditor>()));
    expect(attributes.canEditXattrs, isFalse);
    expect(attributes.xattrs, isEmpty);
  });

  test('умения выведены из присланного, а не из наших надежд', () async {
    final rich = await provider.readAttributes(await node('/srv/notes.txt'));
    final bare = await provider.readAttributes(await node('/srv/bare.txt'));

    expect(rich.canEditMode, isTrue);
    expect(rich.canEditTimes, isTrue);
    expect(rich.canEditOwner, isTrue);

    // Скупой сервер прислал один режим: менять даты и владельца нечем — второй
    // половины пары взять неоткуда.
    expect(bare.canEditMode, isTrue);
    expect(bare.canEditTimes, isFalse);
    expect(bare.canEditOwner, isFalse);
  });

  test('назначает режим, не трогая тип объекта', () async {
    await provider.setMode(await node('/srv/notes.txt'), 0x1ED);

    final now = server.attributesOf('/srv/notes.txt');
    expect(now.mode & 0xFFF, 0x1ED);
    expect(now.mode & ~0xFFF, 0x8000, reason: 'обычный файл им и остался');
  });

  test('обе даты уходят одним пакетом', () async {
    final accessed = DateTime.utc(2021, 5, 5);
    final modified = DateTime.utc(2021, 6, 6);

    await provider.setTimes(await node('/srv/notes.txt'), modified: modified, accessed: accessed);

    expect(server.attributesOf('/srv/notes.txt').modified, modified);
    expect(server.attributesOf('/srv/notes.txt').accessed, accessed);
    expect(server.calls.where((call) => call.startsWith('setstat')), hasLength(1));
  });

  test('одна дата дочитывает вторую', () async {
    final modified = DateTime.utc(2022, 7, 8);

    await provider.setTimes(await node('/srv/notes.txt'), modified: modified);

    final now = server.attributesOf('/srv/notes.txt');
    expect(now.modified, modified);
    // Половину пары протокол не выражает, поэтому вторая приносится
    // прочитанной — и остаётся прежней.
    expect(now.accessed, DateTime.utc(2020, 1, 2, 3, 4, 6));
  });

  test('одно число владельца дочитывает второе', () async {
    await provider.setOwner(await node('/srv/notes.txt'), gid: 50);

    final now = server.attributesOf('/srv/notes.txt');
    expect(now.gid, 50);
    expect(now.uid, 1000);
  });

  test('нечего дочитать — отказ, а не выдумка', () async {
    // Скупой сервер второй даты не присылал, и подставить вместо неё «сейчас»
    // значило бы молча сдвинуть то, чего не просили трогать.
    await expectLater(
      provider.setTimes(await node('/srv/bare.txt'), modified: DateTime.utc(2023)),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notSupported)),
    );
  });

  test('ничего не назначив, сервер не тревожим', () async {
    await provider.setTimes(await node('/srv/notes.txt'));
    await provider.setOwner(await node('/srv/notes.txt'));

    expect(server.calls.where((call) => call.startsWith('setstat')), isEmpty);
  });

  test('несуществующего объекта нет и атрибутов', () async {
    final file = await node('/srv/notes.txt');
    await server.removeFile('/srv/notes.txt');

    await expectLater(
      provider.readAttributes(file),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notFound)),
    );
  });

  test('у ссылки спрашивается цель — как и при назначении', () async {
    final attributes = await provider.readAttributes(await node('/srv/current'));

    // `SSH_FXP_SETSTAT` идёт по ссылке; показывать одно, а менять другое —
    // худший из возможных ответов.
    expect(attributes.modeString, '-rw-r--r--');
  });
}
