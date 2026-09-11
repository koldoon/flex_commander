import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ftp/fc_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Настоящий сервер, настоящий протокол.
///
/// Всё остальное в модуле проверяется на своём сервере (`fake_server.dart`) —
/// он отвечает на вопрос «правильно ли мы говорим». Этот отвечает на другой:
/// **верны ли наши предположения о чужом сервере**. Разбор ответов, форматы
/// списков, коды отказов — всё это догадки до тех пор, пока их не проверишь о
/// живого.
///
/// Куда ходить, говорит `FC_FTP_TEST_HOST`; без неё тест пропускается:
///
/// ```
/// FC_FTP_TEST_HOST=ftp://cios.dhitechnical.com/Cisco \
///   flutter test ftp/test/real_ftp_test.dart
/// ```
///
/// Сервер **чужой и только на чтение**: ничего там не создаём, не удаляем и не
/// переименовываем, а ходим редко и понемногу. Запись проверяется своим
/// сервером — `FC_FTP_WRITE_HOST` (`docs/spec/ftp.md`, §13).
void main() {
  final address = Platform.environment['FC_FTP_TEST_HOST'];
  if (address == null || address.isEmpty) {
    // Пропущенный тест виден в прогоне — молча исчезать он не должен.
    test('живой FTP не проверяется: нет FC_FTP_TEST_HOST', () {}, skip: 'нет FC_FTP_TEST_HOST');
    return;
  }

  final uri = Uri.parse(address);
  final target = FtpTarget.parse(uri);
  final root = uri.path.isEmpty ? '/' : uri.path;

  FtpConnection? connection;

  Future<FtpConnection> connect() async => connection = await FtpConnection.open(target, password: _password(target));

  tearDown(() async {
    await connection?.close();
    connection = null;
  });

  test('вход проходит, несмотря на баннер в два десятка строк', () async {
    final ftp = await connect();

    expect(ftp.isClosed, isFalse);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('сервер объявляет то, на что мы рассчитываем', () async {
    final ftp = await connect();

    expect(ftp.features.machineListing, isTrue, reason: 'MLSD — основной способ читать каталог');
    expect(ftp.features.restart, isTrue, reason: 'без REST нет докачки');
    expect(ftp.features.size, isTrue);
    expect(ftp.features.extendedPassive, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('MLSD читается и разбирается', () async {
    final ftp = await connect();

    final lines = await ftp.listing('MLSD', root);
    expect(lines, isNotEmpty);

    final entries = [
      for (final line in lines)
        if (FtpListing.parseMachine(line) case final entry?) entry,
    ];
    expect(entries, isNotEmpty, reason: 'разобралась хоть одна запись');
    expect(entries.map((entry) => entry.name), isNot(contains('.')), reason: 'cdir выброшен');
    expect(entries.map((entry) => entry.name), isNot(contains('..')), reason: 'pdir выброшен');
    expect(entries.where((entry) => entry.isDirectory), isNotEmpty);
    // Владелец именем — то, чего по SFTP не бывает (`docs/spec/ftp.md`, §3.6).
    expect(entries.first.owner, isNotEmpty);
    expect(entries.first.mode, isNot(0));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('LIST разбирается тем же набором записей', () async {
    // Откат для серверов без MLSD обязан давать то же самое — иначе панель
    // показывает разное в зависимости от сервера.
    final ftp = await connect();

    final machine = {
      for (final line in await ftp.listing('MLSD', root))
        if (FtpListing.parseMachine(line) case final entry?) entry.name,
    };
    final text = {
      for (final line in await ftp.listing('LIST', root))
        if (FtpListing.parseText(line) case final entry?) entry.name,
    };

    expect(text, isNotEmpty);
    expect(text, machine);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('размер спрашивается — значит двоичный режим и правда встал', () async {
    // В ASCII сервер отвечает `550 SIZE not allowed in ASCII mode`, и это
    // ровно та ловушка, ради которой TYPE I ставится сразу после входа
    // (`docs/spec/ftp.md`, §3.3).
    final ftp = await connect();
    final file = await _someFile(ftp, root);

    final reply = await ftp.command('SIZE $file');
    expect(reply.code, 213);
    expect(int.tryParse(reply.message.trim()), greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('кусок файла читается, а докачка начинает с середины', () async {
    final ftp = await connect();
    final file = await _someFile(ftp, root);

    final head = await _take(await ftp.retrieve(file), 64);
    expect(head, hasLength(64));

    final tail = await _take(await ftp.retrieve(file, offset: 32), 32);
    expect(tail, head.sublist(32, 64), reason: 'REST отдал ровно тот же кусок');
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('несуществующий путь — это «не найдено»', () async {
    final ftp = await connect();

    await expectLater(
      ftp.listing('MLSD', '$root/такого-каталога-нет-и-не-будет'),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notFound)),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('FEAT обещает AUTH TLS, а сама команда отказывает', () async {
    // Это не поломка сервера, а причина правила «FEAT — подсказка, а не
    // обещание» (`docs/spec/ftp.md`, §3.2). Если однажды сервер начнёт
    // принимать TLS, тест об этом скажет — и правило надо будет перечитать.
    final ftp = await connect();
    if (!ftp.features.authTls) {
      return;
    }

    final reply = await ftp.command('AUTH TLS');
    expect(reply.isPositive, isFalse, reason: 'сервер объявил AUTH TLS и отказал на нём');
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// Пароль анонимного входа: по обычаю — почтовый адрес.
String _password(FtpTarget target) =>
    target.passwordFromAddress ?? (target.isAnonymous ? FtpTarget.anonymousPassword : '');

/// Какой-нибудь файл под этим каталогом — первый попавшийся.
Future<String> _someFile(FtpConnection ftp, String root) async {
  for (final line in await ftp.listing('MLSD', root)) {
    final entry = FtpListing.parseMachine(line);
    if (entry != null && !entry.isDirectory && entry.size > 1024) {
      return '$root/${entry.name}';
    }
  }
  for (final line in await ftp.listing('MLSD', root)) {
    final entry = FtpListing.parseMachine(line);
    if (entry != null && entry.isDirectory) {
      return _someFile(ftp, '$root/${entry.name}');
    }
  }
  throw StateError('Под $root не нашлось ни одного файла');
}

/// Первые [count] байт потока; остальное не читаем — сервер чужой.
Future<List<int>> _take(Stream<List<int>> stream, int count) async {
  final bytes = <int>[];
  final subscription = stream.listen(null);
  final done = Completer<List<int>>();
  subscription.onData((chunk) {
    bytes.addAll(chunk);
    if (bytes.length >= count && !done.isCompleted) {
      done.complete(bytes.sublist(0, count));
      subscription.cancel();
    }
  });
  subscription.onDone(() {
    if (!done.isCompleted) {
      done.complete(bytes.length >= count ? bytes.sublist(0, count) : bytes);
    }
  });
  subscription.onError((Object error, StackTrace stack) {
    if (!done.isCompleted) {
      done.completeError(error, stack);
    }
  });
  return done.future;
}
