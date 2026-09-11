import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ftp/fc_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

/// Разговор клиента с сервером — через настоящие сокеты.
void main() {
  late FakeFtpServer server;
  FtpConnection? connection;

  tearDown(() async {
    await connection?.close();
    connection = null;
    await server.stop();
  });

  Future<FtpConnection> connect({
    Map<String, Object> files = const {},
    bool machineListing = true,
    bool extendedPassive = true,
  }) async {
    server = await FakeFtpServer.start(files: files, machineListing: machineListing, extendedPassive: extendedPassive);
    final target = FtpTarget.parse(Uri.parse('ftp://user@127.0.0.1:${server.port}/'));
    return connection = await FtpConnection.open(target, password: 'secret');
  }

  group('вход', () {
    test('многострочный баннер не сбивает разговор', () async {
      // Баннер сервера содержит строку, похожую на конец ответа. Если разбор
      // на ней обрывается, дальше врёт весь сеанс — а здесь вход просто не
      // состоится (`docs/spec/ftp.md`, §3.1).
      final ftp = await connect();

      expect(ftp.isClosed, isFalse);
      expect(server.commands.first, 'USER user');
    });

    test('двоичный режим ставится сразу, а не перед передачей', () async {
      // В ASCII нет ни размера, ни докачки, и узнать об этом можно только
      // отказом на SIZE (`docs/spec/ftp.md`, §3.3).
      await connect();

      expect(server.commands, contains('TYPE I'));
      expect(server.commands.indexOf('TYPE I'), lessThan(server.commands.length));
    });

    test('пароль в список команд не попадает', () async {
      await connect();

      expect(server.commands, contains('PASS'));
      expect(server.commands.join(' '), isNot(contains('secret')));
    });

    test('возможности сервера прочитаны', () async {
      final ftp = await connect();

      expect(ftp.features.machineListing, isTrue);
      expect(ftp.features.restart, isTrue);
      expect(ftp.features.size, isTrue);
      expect(ftp.features.setModified, isFalse);
    });

    test('UTF8 объявлен — значит спрашиваем OPTS', () async {
      await connect();

      expect(server.commands, contains('OPTS UTF8 ON'));
    });
  });

  group('канал данных', () {
    test('список каталога приходит строками', () async {
      final ftp = await connect(
        files: {
          '/pub': ['size=10;type=file; a.txt', 'type=dir; вложенный'],
        },
      );

      expect(await ftp.listing('MLSD', '/pub'), ['size=10;type=file; a.txt', 'type=dir; вложенный']);
    });

    test('нет EPSV — берётся PASV', () async {
      final ftp = await connect(
        extendedPassive: false,
        files: {
          '/pub': ['type=file; a.txt'],
        },
      );

      expect(await ftp.listing('MLSD', '/pub'), hasLength(1));
      expect(server.commands, contains('PASV'));
    });

    test('чтение файла отдаёт байты целиком', () async {
      final ftp = await connect(files: {'/pub/a.bin': utf8.encode('здравствуй, сервер')});

      final stream = await ftp.retrieve('/pub/a.bin');
      expect(utf8.decode(await _collect(stream)), 'здравствуй, сервер');
    });

    test('докачка начинает с середины', () async {
      final ftp = await connect(files: {'/pub/a.bin': utf8.encode('0123456789')});

      final stream = await ftp.retrieve('/pub/a.bin', offset: 4);
      expect(utf8.decode(await _collect(stream)), '456789');
      expect(server.commands, contains('REST 4'));
    });

    test('запись кладёт байты на сервер', () async {
      final ftp = await connect();

      await ftp.store('/pub/new.bin', Stream.value(utf8.encode('данные')));
      expect(utf8.decode(server.files['/pub/new.bin']! as List<int>), 'данные');
    });

    test('после передачи соединение годится дальше', () async {
      // Управляющий канал занят на время передачи; если хвост ответа не
      // дочитан, следующая команда прочтёт его вместо своего.
      final ftp = await connect(files: {'/pub/a.bin': utf8.encode('раз')});

      await _collect(await ftp.retrieve('/pub/a.bin'));
      final size = await ftp.command('SIZE /pub/a.bin');

      expect(size.code, 213);
      expect(size.message, '6');
    });
  });

  group('отказы', () {
    test('нет такого файла — «не найдено», а не «нет доступа»', () async {
      final ftp = await connect();

      await expectLater(
        ftp.retrieve('/нет.bin'),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notFound)),
      );
    });

    test('тот же код 550 на записи значит «не разрешено»', () {
      // Живой сервер отвечает 550 и на «нет такого», и на «не позволено», а
      // текст у каждого сервера свой. Решает род команды
      // (`docs/spec/ftp.md`, §3.4).
      final refusal = FtpReply(550, const ['550 /pub/x: Operation not permitted']);

      expect(FtpConnection.errorFor('/pub/x', refusal, writing: true).kind, FsErrorKind.permissionDenied);
      expect(FtpConnection.errorFor('/pub/x', refusal, writing: false).kind, FsErrorKind.notFound);
    });

    test('после отказа соединение продолжает работать', () async {
      final ftp = await connect(
        files: {
          '/pub': ['type=file; a.txt'],
        },
      );

      await expectLater(ftp.listing('MLSD', '/нет'), throwsA(isA<FsError>()));
      expect(await ftp.listing('MLSD', '/pub'), hasLength(1));
    });

    test('закрытое соединение отвечает отказом, а не молчанием', () async {
      final ftp = await connect();
      await ftp.close();

      expect(ftp.isClosed, isTrue);
      await expectLater(ftp.command('PWD'), throwsA(isA<FsError>()));
    });
  });

  group('очередь', () {
    test('команды не перемешиваются', () async {
      // У FTP один управляющий канал: два запроса разом означали бы, что
      // ответ одного достался другому (`docs/spec/ftp.md`, §5).
      final ftp = await connect(files: {'/a.bin': utf8.encode('12345'), '/b.bin': utf8.encode('67')});

      final replies = await Future.wait([ftp.command('SIZE /a.bin'), ftp.command('SIZE /b.bin')]);

      expect(replies[0].message, '5');
      expect(replies[1].message, '2');
    });
  });
}

Future<List<int>> _collect(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return bytes;
}
