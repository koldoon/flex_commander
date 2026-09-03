import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Настоящий сервер, настоящий протокол.
///
/// Всё остальное в модуле проверяется на подставном SFTP — иначе тесты
/// требовали бы сервера на каждой машине. Но подставка проверяет наши
/// предположения о протоколе, а не сам протокол: разбор атрибутов, порядок
/// вызовов, коды ошибок. Этот тест проверяет предположения — и потому
/// включается только там, где есть куда ходить.
///
/// Куда ходить, говорит `FC_SSH_TEST_HOST`; без неё — `localhost`:
///
/// ```
/// FC_SSH_TEST_HOST=koldoon@192.168.42.2 flutter test ssh/test/real_ssh_test.dart
/// ```
///
/// На сервере нужен вход по ключу без пароля (`ssh-copy-id`): [FakeCredentials]
/// без ответов отказывает на любой вопрос, поэтому дошедший до конца тест
/// заодно доказывает, что вход прошёл именно по ключу.
///
/// Ссылки и права ставятся системным клиентом `ssh`: SFTP этого не умеет, а
/// подделывать обстановку в тесте о настоящем сервере — значит проверять не то.
void main() {
  final hostSpec = Platform.environment['FC_SSH_TEST_HOST'] ?? 'localhost';
  final target = SshTarget.parse(Uri.parse('ssh://$hostSpec/'));

  late FakeCredentials credentials;
  SshConnection? connection;
  SftpTreeProvider? provider;
  DirectoryNode? work;
  Directory? localWork;

  Future<SftpTreeProvider?> connect() async {
    credentials = FakeCredentials();
    try {
      final opened = await SshConnection.open(
        target: target,
        credentials: credentials,
        timeout: const Duration(seconds: 8),
      );
      connection = opened;
      return provider = SftpTreeProvider(
        target: target,
        sftp: opened.sftp,
        homePath: opened.homePath,
        connection: opened,
      );
    } on FsError {
      return null;
    }
  }

  /// Команда на сервере системным клиентом — только для того, чего нет в SFTP.
  Future<void> remoteShell(String command) async {
    final result = await Process.run('ssh', ['-o', 'BatchMode=yes', hostSpec, command]);
    if (result.exitCode != 0) {
      throw StateError('на сервере не вышло «$command»: ${result.stderr}');
    }
  }

  /// Свой каталог на время теста — внутри дома, как его видит сервер.
  Future<DirectoryNode> workDirectory(SftpTreeProvider provider) async {
    final home = await provider.resolvePath().run(provider.homePath) as DirectoryNode;
    return work = await provider.createDirectory(home, 'flex_commander_test_$pid');
  }

  String remote(DirectoryNode dir, [String name = '']) =>
      name.isEmpty ? provider!.remotePathOf(dir) : p.posix.join(provider!.remotePathOf(dir), name);

  Future<String> readRemote(String path) async {
    final node = await provider!.resolvePath().run(path);
    final bytes = <int>[];
    await for (final chunk in await provider!.openRead(node!)) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<void> writeRemote(DirectoryNode parent, String name, String content) async {
    final sink = await provider!.openWrite(parent, name, length: utf8.encode(content).length);
    await sink.addStream(Stream<List<int>>.value(utf8.encode(content)));
    await sink.close();
  }

  tearDown(() async {
    final leftover = work;
    if (leftover != null) {
      // Через оболочку, а не через модуль: убирать за собой нужно и после
      // упавшего теста, в том числе если упало как раз удаление.
      await remoteShell("rm -rf '${provider!.remotePathOf(leftover)}'").catchError((_) {});
    }
    work = null;

    await connection?.close();
    connection = null;
    provider = null;

    if (localWork != null && await localWork!.exists()) {
      await localWork!.delete(recursive: true);
    }
    localWork = null;
  });

  test('сервер отвечает — или тест пропущен', () async {
    if (await connect() == null) {
      markTestSkipped('$hostSpec не пускает по ключу: ssh-copy-id $hostSpec');
      return;
    }

    expect(provider!.homePath, startsWith('/'));
    // Ни одного вопроса: вошли по ключу.
    expect(credentials.asked, isEmpty);
  });

  test('одиночное нажатие доходит до сервера сразу', () async {
    final provider = await connect();
    if (provider == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }

    // Спрашиваем **терминал сервера**, а не оболочку: `cat` ввод не толкует, а
    // драйвер терминала отражает нажатое сразу — `Esc` виден как `^[`.
    //
    // Проверка появилась из жалобы «`Esc` на удалённом приходится нажимать
    // дважды». Оболочка на это не ответчик: `bash` держит `Esc` как приставку и
    // ждёт продолжения, а `zsh` на своей машине по своему сроку его отпускает —
    // отсюда и разница, которую видно глазами. Здесь проверяется наше: байт
    // ушёл один и ушёл сразу.
    final pty = await provider.run('cat', directory: '/tmp');
    final seen = StringBuffer();
    final output = pty.output.listen((chunk) => seen.write(utf8.decode(chunk, allowMalformed: true)));
    addTearDown(() async {
      await output.cancel();
      await pty.kill();
    });

    // Дать оболочке сервера открыться и утихнуть.
    await Future<void>.delayed(const Duration(seconds: 2));
    seen.clear();

    pty.write(Uint8List.fromList([0x1b]));
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(seen.toString(), '^[', reason: 'один байт, и сразу — без второго нажатия');
  });

  test('панель видит дерево так же, как сервер', () async {
    final provider = await connect();
    if (provider == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }

    final dir = await workDirectory(provider);
    final path = remote(dir);
    await remoteShell(
      "mkdir -p '$path/docs' && printf 'заметки' > '$path/notes.txt' "
      "&& ln -s docs '$path/current' && ln -s nowhere '$path/broken' "
      "&& printf 'x' > '$path/.hidden'",
    );

    final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
    final names = nodes.map((node) => node.name).toList();

    expect(names.first, '..');
    expect(names, containsAll(['notes.txt', 'docs', 'current', 'broken']));
    expect(names, isNot(contains('.hidden')));

    final file = nodes.firstWhere((node) => node.name == 'notes.txt') as FileNode;
    expect(file.size, utf8.encode('заметки').length);
    expect(file.attributes.modeString, startsWith('-rw'));
    expect(file.modified, isNotNull);
    expect(file.modified!.difference(DateTime.now()).inMinutes.abs(), lessThan(5));

    final link = nodes.firstWhere((node) => node.name == 'current') as LinkNode;
    expect(link.reference, 'docs');
    expect(link.isDirectoryLink, isTrue);
    expect(link.broken, isFalse);
    expect(link.attributes.modeString, startsWith('l'));

    final broken = nodes.firstWhere((node) => node.name == 'broken') as LinkNode;
    expect(broken.broken, isTrue);

    final docs = nodes.firstWhere((node) => node.name == 'docs');
    expect(docs, isA<DirectoryNode>());
    expect(docs.pathString, 'ssh://${target.user}@${target.host}$path/docs');

    // Скрытое по требованию видно.
    expect(
      (await provider.getDirectoryListing().run(ListingParams(dir, includeHidden: true))).map((node) => node.name),
      contains('.hidden'),
    );

    // И через ссылку на каталог ходится.
    expect(await provider.resolvePath().run('$path/current'), isA<LinkNode>());
    await writeRemote(await provider.resolvePath().run('$path/docs') as DirectoryNode, 'guide.txt', 'руководство');
    expect(await readRemote('$path/current/guide.txt'), 'руководство');
  });

  test('копирование движком в обе стороны', () async {
    final provider = await connect();
    if (provider == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }

    const engine = TreeTransferEngine();
    final local = LocalTreeProvider(readInIsolate: false);
    final dir = await workDirectory(provider);

    // Наверх: каталог с вложенностью и файлом больше одного куска.
    localWork = await Directory.systemTemp.createTemp('fc_ssh_live');
    final outgoing = Directory(p.join(localWork!.path, 'outgoing', 'nested'));
    await outgoing.create(recursive: true);
    await File(p.join(localWork!.path, 'outgoing', 'report.txt')).writeAsString('отчёт');
    final big = List<int>.generate(256 * 1024, (i) => i % 256);
    await File(p.join(outgoing.path, 'deep.bin')).writeAsBytes(big);

    final source = await local.resolvePath().run(p.join(localWork!.path, 'outgoing'));
    await engine.copy().run(TransferParams([source!], dir));

    final path = remote(dir);
    expect(await readRemote('$path/outgoing/report.txt'), 'отчёт');

    final uploaded = await provider.resolvePath().run('$path/outgoing/nested/deep.bin');
    expect(uploaded, isNotNull);
    expect((uploaded! as FileNode).size, big.length);

    // И обратно: тот же файл забираем к себе и сверяем байты.
    final back = await Directory(p.join(localWork!.path, 'back')).create();
    await engine.copy().run(TransferParams([uploaded], (await local.resolvePath().run(back.path)) as DirectoryNode));

    final returned = await File(p.join(back.path, 'deep.bin')).readAsBytes();
    expect(returned, hasLength(big.length));
    expect(returned, equals(big));
  });

  test('чтение с середины файла — настоящее', () async {
    final provider = await connect();
    if (provider == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }

    final dir = await workDirectory(provider);
    await writeRemote(dir, 'tail.txt', 'начало-и-конец');

    final node = await provider.resolvePath().run('${remote(dir)}/tail.txt');
    final bytes = <int>[];
    await for (final chunk in await provider.openRead(node!, offset: utf8.encode('начало-и-').length)) {
      bytes.addAll(chunk);
    }

    expect(utf8.decode(bytes), 'конец');
  });

  test('каталоги, переименование и удаление', () async {
    final provider = await connect();
    if (provider == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }

    final dir = await workDirectory(provider);

    final logs = await provider.createDirectory(dir, 'logs');
    expect(await provider.resolvePath().run(remote(dir, 'logs')), isA<DirectoryNode>());

    // Занятое имя — внятный ответ, а не общий отказ сервера.
    await expectLater(
      () => provider.createDirectory(dir, 'logs'),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.alreadyExists)),
    );

    await writeRemote(logs, 'app.log', 'строка');
    final logFile = await provider.resolvePath().run(remote(logs, 'app.log'));

    expect(await provider.renameEntry(logFile!, dir, 'moved.log'), isTrue);
    expect(await readRemote(remote(dir, 'moved.log')), 'строка');
    expect(await provider.resolvePath().run(remote(logs, 'app.log')), isNull);

    final moved = await provider.resolvePath().run(remote(dir, 'moved.log'));
    await provider.deleteEntry(moved!);
    expect(await provider.resolvePath().run(remote(dir, 'moved.log')), isNull);

    await provider.deleteEntry(logs);
    expect(await provider.resolvePath().run(remote(dir, 'logs')), isNull);
  });

  test('удаление поддерева — движком, по одному объекту', () async {
    final provider = await connect();
    if (provider == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }

    const engine = TreeTransferEngine();
    final dir = await workDirectory(provider);
    await remoteShell("mkdir -p '${remote(dir)}/tree/inner' && printf 'a' > '${remote(dir)}/tree/inner/a.txt'");

    final tree = await provider.resolvePath().run(remote(dir, 'tree'));

    // Корзины на сервере нет, поэтому удаление окончательное — движок обходит
    // поддерево сам.
    await engine.remove().run(RemoveParams([tree!], toTrash: false));

    expect(await provider.resolvePath().run(remote(dir, 'tree')), isNull);
  });

  test('панель встаёт на сервер целиком и уходит с него', () async {
    // Здесь проверяется не протокол, а сборка: объявление схемы модулем,
    // реестр, панель. Приложение настоящее, со всеми модулями — только
    // локальный источник подставной, чтобы тест не зависел от этой машины.
    if (await connect() == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }
    await connection!.close();
    connection = null;

    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();

    final panel = runtime.app.left;
    final session = runtime.app.leftSession;
    expect(await panel.openPath('ssh://$hostSpec/'), isTrue);

    // Панель стоит на сервере: её корень — не общий.
    expect(session.provider.scheme, 'ssh');
    expect(session.directory!.pathString, startsWith('ssh://'));
    expect(panel.entries, isNotEmpty);

    // Путь без схемы возвращает на общий корень, а соединение закрывается:
    // держать его больше некому.
    final server = session.provider;
    expect(await panel.openPath('/home'), isTrue);
    expect(session.provider.scheme, isNot('ssh'));
    expect(
      () => (server as SftpTreeProvider).getDirectoryListing().run(ListingParams(server.rootDirectory)),
      throwsA(anything),
    );
  });

  test('архив на сервере открывается показанным путём', () async {
    // Самое дальнее, что есть в приложении: показанный путь без схемы архива,
    // над сервером, куда архив ещё и приезжает временной копией
    // (`LocalCopySession`). Каждый кусок этого проверен по отдельности —
    // здесь они впервые работают вместе и по-настоящему.
    final provider = await connect();
    if (provider == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }

    final dir = await workDirectory(provider);

    // Архив собирается здесь и уезжает на сервер нашим же приёмником байтов.
    localWork = await Directory.systemTemp.createTemp('fc_ssh_zip');
    await Directory(p.join(localWork!.path, 'docs')).create();
    await File(p.join(localWork!.path, 'docs', 'guide.txt')).writeAsString('руководство');
    final built = await Process.run('zip', ['-r', 'sample.zip', 'docs'], workingDirectory: localWork!.path);
    if (built.exitCode != 0) {
      markTestSkipped('нет программы zip, собрать архив нечем');
      return;
    }

    final bytes = await File(p.join(localWork!.path, 'sample.zip')).readAsBytes();
    final sink = await provider.openWrite(dir, 'sample.zip', length: bytes.length);
    await sink.addStream(Stream<List<int>>.value(bytes));
    await sink.close();

    await connection!.close();
    connection = null;

    // Приложение настоящее, со всеми модулями: схему `zip` объявляет свой
    // модуль, схему `ssh` — свой, а связывает их реестр.
    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();

    final panel = runtime.app.left;
    final session = runtime.app.leftSession;
    final shown = 'ssh://$hostSpec${remote(dir)}/sample.zip/docs';

    expect(await panel.openPath(shown), isTrue);

    expect(session.provider.scheme, 'zip');
    expect(panel.entries.map((node) => node.name), contains('guide.txt'));
    // И круг замыкается: показанное совпадает с тем, что открывали.
    expect(session.directory?.displayPath, shown);
  });

  test('чего нет — того нет, а закрытое закрыто', () async {
    final provider = await connect();
    if (provider == null) {
      markTestSkipped('$hostSpec не пускает по ключу');
      return;
    }

    final dir = await workDirectory(provider);
    expect(await provider.resolvePath().run(remote(dir, 'нет-такого')), isNull);

    await remoteShell(
      "mkdir -p '${remote(dir)}/closed' && printf 'тайна' > '${remote(dir)}/closed/secret' "
      "&& chmod 000 '${remote(dir)}/closed'",
    );

    final closed = await provider.resolvePath().run(remote(dir, 'closed'));
    try {
      await expectLater(
        () => provider.getDirectoryListing().run(ListingParams(closed as DirectoryNode)),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.permissionDenied)),
      );
    } finally {
      await remoteShell("chmod 755 '${remote(dir)}/closed'");
    }
  });
}
