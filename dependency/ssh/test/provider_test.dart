import 'dart:convert';
import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flutter/foundation.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sftp.dart';

void main() {
  late FakeSftp server;
  late SftpTreeProvider provider;

  setUp(() {
    server = FakeSftp();
    server.directory('/srv');
    // На настоящем сервере он есть всегда; повышение кладёт туда временный.
    server.directory('/tmp');
    server.directory('/srv/www');
    server.file('/srv/www/index.html', '<html/>');
    server.file('/srv/notes.txt', 'заметки');
    server.file('/srv/.hidden', 'скрытое');
    server.link('/srv/current', '/srv/www');
    server.link('/srv/broken', '/srv/gone');

    provider = SftpTreeProvider(
      target: SshTarget.parse(Uri.parse('ssh://tester@example.org/')),
      sftp: server,
      homePath: server.home,
    );
  });

  Future<DirectoryNode> open(String path) async {
    final node = await provider.resolvePath().run(path);
    return node as DirectoryNode;
  }

  group('пути', () {
    test('путь узла — полный адрес сервера', () async {
      final node = await provider.resolvePath().run('/srv/notes.txt');

      expect(node!.pathString, 'ssh://tester@example.org/srv/notes.txt');
      expect(provider.remotePathOf(node), '/srv/notes.txt');
    });

    test('корень тоже адресуется', () {
      expect(provider.rootDirectory.pathString, 'ssh://tester@example.org/');
      expect(provider.remotePathOf(provider.rootDirectory), '/');
    });

    test('разбирается и с началом адреса, и без него', () async {
      final withAuthority = await provider.resolvePath().run('//tester@example.org/srv/notes.txt');
      final plain = await provider.resolvePath().run('/srv/notes.txt');

      expect(withAuthority, isNotNull);
      expect(withAuthority!.pathString, plain!.pathString);
    });

    test('которого нет — null, а не ошибка', () async {
      expect(await provider.resolvePath().run('/srv/missing'), isNull);
      expect(await provider.resolvePath().run('/srv/notes.txt/deeper'), isNull);
    });

    test('цепочка узлов доходит до корня — панели есть куда идти наверх', () async {
      final node = await provider.resolvePath().run('/srv/www/index.html');

      expect(node!.path.map((n) => n.name).toList(), ['/', 'srv', 'www', 'index.html']);
      expect(identical(node.path.first, provider.rootDirectory), isTrue);
    });

    test('через ссылку на каталог — видимый путь идёт по ссылке', () async {
      final node = await provider.resolvePath().run('/srv/current/index.html');

      expect(node, isNotNull);
      expect(provider.remotePathOf(node!), '/srv/current/index.html');
      expect(node.pathString, 'ssh://tester@example.org/srv/current/index.html');
    });
  });

  group('чтение каталога', () {
    test('скрытое по умолчанию не показывается, «..» есть', () async {
      final dir = await open('/srv');
      final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
      final names = nodes.map((node) => node.name).toList();

      expect(names.first, '..');
      expect(names, containsAll(['www', 'notes.txt', 'current', 'broken']));
      expect(names, isNot(contains('.hidden')));
    });

    test('скрытое по требованию показывается', () async {
      final dir = await open('/srv');
      final nodes = await provider.getDirectoryListing().run(ListingParams(dir, includeHidden: true));

      expect(nodes.map((node) => node.name), contains('.hidden'));
    });

    test('в корне «..» нет', () async {
      final nodes = await provider.getDirectoryListing().run(ListingParams(provider.rootDirectory));

      expect(nodes.map((node) => node.name), isNot(contains('..')));
    });

    test('ссылка знает про цель, битая — про то, что цели нет', () async {
      final dir = await open('/srv');
      final nodes = await provider.getDirectoryListing().run(ListingParams(dir));

      final current = nodes.firstWhere((node) => node.name == 'current') as LinkNode;
      expect(current.reference, '/srv/www');
      expect(current.isDirectoryLink, isTrue);
      expect(current.broken, isFalse);

      final broken = nodes.firstWhere((node) => node.name == 'broken') as LinkNode;
      expect(broken.broken, isTrue);
      expect(broken.isDirectoryLink, isFalse);
    });

    test('обход движка не подменяет то, что показывает панель', () async {
      final dir = await open('/srv');
      await provider.getDirectoryListing().run(ListingParams(dir));
      final shown = dir.nodes;

      final children = await provider.listChildren(dir);

      expect(children.map((node) => node.name), isNot(contains('..')));
      expect(children.map((node) => node.name), contains('.hidden'));
      expect(identical(dir.nodes, shown), isTrue);
    });

    test('закрытый каталог — отказ, а не пустота', () async {
      final dir = await open('/srv/www');
      server.denied['/srv/www'] = FsErrorKind.permissionDenied;

      expect(
        () => provider.getDirectoryListing().run(ListingParams(dir)),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.permissionDenied)),
      );
    });

    test('ссылка разворачивается в цель, а та помнит ссылку родителем', () async {
      final dir = await open('/srv');
      final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
      final link = nodes.firstWhere((node) => node.name == 'current') as LinkNode;

      final target = await provider.resolveLink().run(link);

      expect(target, isA<DirectoryNode>());
      expect(target!.name, 'www');
      expect(identical(target.parent, link), isTrue);
      expect(identical(link.target, target), isTrue);
    });
  });

  group('изменение дерева', () {
    test('каталог создаётся и сразу виден узлом', () async {
      final parent = await open('/srv');
      final created = await provider.createDirectory(parent, 'logs');

      expect(created.name, 'logs');
      expect(server.has('/srv/logs'), isTrue);
      expect(created.pathString, 'ssh://tester@example.org/srv/logs');
    });

    test('занятое имя — «уже есть», а не общий отказ', () async {
      final parent = await open('/srv');

      expect(
        () => provider.createDirectory(parent, 'www'),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.alreadyExists)),
      );
    });

    test('негодное имя до сервера не доходит', () async {
      final parent = await open('/srv');

      for (final name in ['', '.', '..', 'a/b']) {
        await expectLater(
          () => provider.createDirectory(parent, name),
          throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.invalidName)),
        );
      }
      expect(server.calls.where((call) => call.startsWith('mkdir')), isEmpty);
    });

    test('переименование внутри сервера — одним действием', () async {
      final source = await provider.resolvePath().run('/srv/notes.txt');
      final destination = await open('/srv/www');

      expect(await provider.renameEntry(source!, destination, 'readme.txt'), isTrue);
      expect(server.has('/srv/www/readme.txt'), isTrue);
      expect(server.has('/srv/notes.txt'), isFalse);
    });

    test('в чужой источник переименованием не уехать', () async {
      final source = await provider.resolvePath().run('/srv/notes.txt');
      final elsewhere = InMemoryContentProvider();

      expect(await provider.renameEntry(source!, elsewhere.rootDirectory, 'readme.txt'), isFalse);
      expect(server.calls.where((call) => call.startsWith('rename')), isEmpty);
    });

    test('копии средствами сервера нет — движку сказано прямо', () async {
      final source = await provider.resolvePath().run('/srv/notes.txt');
      final destination = await open('/srv/www');

      expect(await provider.copyEntry(source!, destination, 'notes.txt'), isFalse);
    });

    test('удаляются и файл, и пустой каталог, и сама ссылка', () async {
      final file = await provider.resolvePath().run('/srv/notes.txt');
      await provider.deleteEntry(file!);
      expect(server.has('/srv/notes.txt'), isFalse);

      final link = await provider.resolvePath().run('/srv/current');
      await provider.deleteEntry(link!);
      expect(server.has('/srv/current'), isFalse);
      // Цель ссылки на месте: удаляли ссылку, а не то, куда она вела.
      expect(server.has('/srv/www'), isTrue);

      final directory = await provider.resolvePath().run('/srv/www/index.html');
      await provider.deleteEntry(directory!);
      await provider.deleteEntry((await open('/srv/www')));
      expect(server.has('/srv/www'), isFalse);
    });

    test('корзины и удаления поддерева нет — рекурсию ведёт движок', () async {
      final node = await provider.resolvePath().run('/srv/www');

      expect(await provider.trashEntry(node!), isFalse);
      expect(await provider.deleteTree(node), isFalse);
    });

    test('тот же объект и объект внутри себя', () async {
      final node = await provider.resolvePath().run('/srv/www');
      final srv = await open('/srv');

      expect(provider.isSameEntity(node!, srv), isTrue);
      expect(provider.isInsideSource(srv, srv), isTrue);
      expect(provider.isSameEntity(node, await open('/srv/www')), isFalse);
    });
  });

  group('байты', () {
    test('читается целиком и с середины', () async {
      final node = await provider.resolvePath().run('/srv/www/index.html');

      expect(utf8.decode(await _collect(await provider.openRead(node!))), '<html/>');
      expect(utf8.decode(await _collect(await provider.openRead(node, offset: 6))), '>');
    });

    test('записывается новым файлом', () async {
      final parent = await open('/srv/www');
      final sink = await provider.openWrite(parent, 'about.html', length: 5);

      await sink.addStream(Stream<List<int>>.value(utf8.encode('здесь')));
      await sink.close();

      expect(server.contentOf('/srv/www/about.html'), 'здесь');
    });
  });

  group('подсчёт', () {
    test('размер поддерева — только файлы', () async {
      final node = await provider.resolvePath().run('/srv');

      final total = await provider.calculateSize().run([node!]);

      // <html/> (7) + заметки (14 байт в utf-8) + скрытое (14). Ссылки байтов
      // не переносят, у каталогов их нет.
      expect(total, 7 + utf8.encode('заметки').length + utf8.encode('скрытое').length);
    });

    test('обход считает и сам объект, и всё под ним', () async {
      final node = await provider.resolvePath().run('/srv/www');
      final sizes = <int>[];

      await provider.countEntries(node!, sizes.add);

      expect(sizes, hasLength(2)); // сам каталог и index.html
      expect(sizes.reduce((a, b) => a + b), 7);
    });

    test('закрытый подкаталог обход не обрывает', () async {
      server.directory('/srv/locked');
      server.file('/srv/locked/secret', 'x');
      server.denied['/srv/locked'] = FsErrorKind.permissionDenied;

      final node = await provider.resolvePath().run('/srv');
      final total = await provider.calculateSize().run([node!]);

      expect(total, greaterThan(0));
    });
  });

  group('соединение', () {
    test('закрывается вместе с провайдером', () async {
      await provider.dispose();

      expect(server.closed, isTrue);
    });
  });

  group('перенос движком', () {
    late TreeEditor engine;
    late InMemoryContentProvider local;

    setUp(() {
      engine = const TreeTransferEngine();
      local = InMemoryContentProvider();
    });

    test('с сервера к себе', () async {
      final source = await provider.resolvePath().run('/srv/notes.txt');

      await engine.copy().run(TransferParams([source!], local.rootDirectory));

      final copied = await local.resolvePath().run('/notes.txt');
      expect(copied, isNotNull);
      expect(utf8.decode(await _collect(await local.openRead(copied!))), 'заметки');
    });

    test('к себе целым каталогом', () async {
      final source = await provider.resolvePath().run('/srv/www');

      await engine.copy().run(TransferParams([source!], local.rootDirectory));

      expect(await local.resolvePath().run('/www/index.html'), isNotNull);
    });

    test('от себя на сервер', () async {
      await local.createDirectory(local.rootDirectory, 'out');
      final outgoing = await local.resolvePath().run('/out') as DirectoryNode;
      final sink = await local.openWrite(outgoing, 'report.txt', length: null);
      await sink.addStream(Stream<List<int>>.value(utf8.encode('отчёт')));
      await sink.close();

      final source = await local.resolvePath().run('/out/report.txt');
      final destination = await provider.resolvePath().run('/srv/www') as DirectoryNode;

      await engine.copy().run(TransferParams([source!], destination));

      expect(server.contentOf('/srv/www/report.txt'), 'отчёт');
    });

    test('перенос внутри сервера идёт переименованием', () async {
      final source = await provider.resolvePath().run('/srv/notes.txt');
      final destination = await provider.resolvePath().run('/srv/www') as DirectoryNode;

      await engine.move().run(TransferParams([source!], destination));

      expect(server.has('/srv/www/notes.txt'), isTrue);
      expect(server.has('/srv/notes.txt'), isFalse);
      expect(server.calls.where((call) => call.startsWith('rename')), hasLength(1));
    });
  });

  group('право записи', () {
    Future<FsNode> fileAt(String path) async {
      final node = await provider.resolvePath().run(path);
      return node!;
    }

    test('спрашивается у сервера, а не выводится из прав владельца', () async {
      final node = await fileAt('/srv/notes.txt');
      server.calls.clear();

      expect(await provider.canWriteTo(node), isTrue);
      expect(server.calls, contains('canWriteTo /srv/notes.txt'));
    });

    test('отказ сервера — это «нельзя», а не исключение', () async {
      final node = await fileAt('/srv/notes.txt');
      server.denied['/srv/notes.txt'] = FsErrorKind.permissionDenied;

      expect(await provider.canWriteTo(node), isFalse);
    });

    test('провайдер объявляет это умение — иначе о нём никто не спросит', () {
      expect(provider, isA<WriteAccessCheck>());
    });
  });

  group('оболочка на той стороне', () {
    test('умение объявлено, и место названо человеку понятно', () {
      expect(provider, isA<ShellHost>());
      expect(provider.shellLabel, 'tester@example.org');
    });

    test('каталог уходит обёрткой, а не досылкой', () {
      // Ошибочный `cd` виден сразу: команда не выполнится молча не там.
      expect(SftpTreeProvider.commandIn('/srv/www', 'ls'), "cd -- '/srv/www' && ls");
    });

    test('без каталога команда идёт как есть', () {
      expect(SftpTreeProvider.commandIn(null, 'ls'), 'ls');
    });

    test('каталог с кавычкой не разваливает команду', () {
      expect(SftpTreeProvider.quoteForShell("it's"), r"'it'\''s'");
    });

    test('каталог, похожий на ключ, остаётся каталогом', () {
      // Без `--` каталог `-rf` стал бы ключом `cd`.
      expect(SftpTreeProvider.commandIn('-rf', 'ls'), startsWith('cd -- '));
    });
  });

  group('запись через повышение', () {
    /// Повышение, которое запоминает, о чём просили.
    _FakeElevation elevation({bool enabled = true, bool succeeds = true}) =>
        _FakeElevation(enabled: enabled, succeeds: succeeds);

    Future<StreamSink<List<int>>> write(SftpTreeProvider provider, String name) async {
      final root = await provider.resolvePath().run('/srv');
      return provider.openWrite(root! as DirectoryNode, name);
    }

    SftpTreeProvider providerWith(_FakeElevation service) => SftpTreeProvider(
      target: SshTarget.parse(Uri.parse('ssh://tester@example.org/')),
      sftp: server,
      homePath: server.home,
      elevation: () => service,
    );

    test('сервер отказал — байты уходят во временный файл на нём же', () async {
      // Живой случай: /etc/squid/squid.conf по ssh.
      server.denied['/srv/squid.conf'] = FsErrorKind.permissionDenied;
      final service = elevation();

      final sink = await write(providerWith(service), 'squid.conf');
      sink.add(utf8.encode('правленое'));
      await sink.close();

      expect(service.asked, hasLength(1));
      expect(service.asked.single.where, 'tester@example.org', reason: 'место — тот самый сервер');
      expect(service.asked.single.path, '/srv/squid.conf');
      // Временный лежит **на сервере**: sudo выполняется там, и путь ему нужен
      // тамошний.
      expect(service.temporary, startsWith('/tmp/fc-elevated-'));
    });

    test('отказались — это отказ по правам, а не тишина', () async {
      server.denied['/srv/squid.conf'] = FsErrorKind.permissionDenied;
      final sink = await write(providerWith(elevation(succeeds: false)), 'squid.conf');
      sink.add(utf8.encode('мимо'));

      await expectLater(sink.close(), throwsA(isA<FsError>()));
    });

    test('выключенное повышение оставляет отказ как был', () async {
      server.denied['/srv/squid.conf'] = FsErrorKind.permissionDenied;

      await expectLater(
        write(providerWith(elevation(enabled: false)), 'squid.conf'),
        throwsA(isA<FsError>()),
        reason: 'отказ приходит сразу, из самого openWrite',
      );
    });

    test('там, где прав хватило, повышения не трогаем', () async {
      final service = elevation();
      final sink = await write(providerWith(service), 'plain.txt');
      sink.add(utf8.encode('обычная запись'));
      await sink.close();

      expect(service.asked, isEmpty);
    });
  });
}

/// Повышение, которое запоминает, о чём просили, и ничего не делает.
class _FakeElevation implements Elevation {
  _FakeElevation({required this.enabled, required this.succeeds});

  @override
  final bool enabled;

  final bool succeeds;

  final List<ElevationRequest> asked = [];

  /// Куда провайдер положил временный файл.
  String? temporary;

  @override
  Future<bool> copyOver({
    required ShellHost host,
    required String temporary,
    required String target,
    required ElevationRequest about,
  }) async {
    asked.add(about);
    this.temporary = temporary;
    return succeeds;
  }

  @override
  ElevationRequest? get pending => null;

  @override
  void answer(bool agreed) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

Future<List<int>> _collect(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return bytes;
}
