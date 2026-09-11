import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ftp/fc_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

/// Сорванная передача — то, из-за чего панель говорила «not supported» про
/// сервер, с которым только что разговаривала.
///
/// Сам обрыв канала данных **не наша ошибка**: тот же обмен минимальным
/// клиентом, без единой нашей строки, срывается примерно раз на сорок. Здесь
/// проверяется то, что было нашим: соединение не должно сбиваться с такта,
/// ошибка должна доходить на языке дерева, а переходный отказ — повторяться
/// (`docs/spec/ftp.md`, §3.7).
///
/// Настоящий обрыв на петле детерминированно не воспроизвести — подставной
/// сервер отвечает переходным `425`, а обрыв как таковой ловит живой тест.
void main() {
  late FakeFtpServer server;
  FtpConnection? connection;

  tearDown(() async {
    await connection?.close();
    connection = null;
    await server.stop();
  });

  Future<FtpConnection> connect() async {
    server = await FakeFtpServer.start(
      files: {
        '/pub': ['type=file; a.txt', 'type=dir; вложенный'],
        '/pub/big.bin': utf8.encode('0123456789' * 2000),
      },
    );
    final target = FtpTarget.parse(Uri.parse('ftp://user@127.0.0.1:${server.port}/'));
    return connection = await FtpConnection.open(target, password: 'secret');
  }

  group('переходный отказ канала', () {
    test('приходит ошибкой ввода-вывода, а не «нет файла»', () async {
      // «Не найдено» повтором не лечится, а это — лечится: разница
      // существенная, и по ней принимается решение повторять.
      final ftp = await connect();
      server.refuseTransfers = 1;

      await expectLater(
        ftp.listing('MLSD', '/pub'),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.io)),
      );
    });

    test('не сбивает управляющий канал с такта', () async {
      // Сдвиг ответов на единицу и был причиной «not supported»: EPSV получал
      // чужой ответ, PASV — тоже, порт не разбирался ни там ни там.
      final ftp = await connect();
      server.refuseTransfers = 1;

      await expectLater(ftp.listing('MLSD', '/pub'), throwsA(isA<FsError>()));

      final reply = await ftp.command('PWD');
      expect(reply.code, 257, reason: 'ответ достался своей команде');
    });

    test('источник повторяет сам, и человек об этом не знает', () async {
      final ftp = await connect();
      final api = FtpOverConnection(ftp);
      server.refuseTransfers = 2;

      final entries = await api.listDirectory('/pub');
      expect(entries.map((entry) => entry.name), ['a.txt', 'вложенный']);
    });

    test('но повторяет не бесконечно', () async {
      final ftp = await connect();
      final api = FtpOverConnection(ftp);
      server.refuseTransfers = 99;

      await expectLater(
        api.listDirectory('/pub'),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.io)),
      );
    });

    test('«не найдено» не повторяется вовсе', () async {
      final ftp = await connect();
      final api = FtpOverConnection(ftp);

      await expectLater(
        api.listDirectory('/нет-такого'),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notFound)),
      );
      expect(server.commands.where((command) => command.startsWith('MLSD')), hasLength(1));
    });
  });

  group('прерванное чтение', () {
    test('соединение остаётся годным', () async {
      // Бросили файл на середине — сервер об этом ещё не знает, и его хвост
      // надо дочитать, иначе следующая команда прочтёт чужой ответ.
      final ftp = await connect();

      final stream = await ftp.retrieve('/pub/big.bin');
      final subscription = stream.listen(null);
      await subscription.cancel();

      final reply = await ftp.command('PWD');
      expect(reply.code, 257);
    });
  });
}
