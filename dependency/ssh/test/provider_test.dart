import 'dart:convert';

import 'package:fc_api/fc_api.dart';
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
    final node = await provider.resolvePath(path).result;
    return node as DirectoryNode;
  }

  group('пути', () {
    test('путь узла — полный адрес сервера', () async {
      final node = await provider.resolvePath('/srv/notes.txt').result;

      expect(node!.pathString, 'ssh://tester@example.org/srv/notes.txt');
      expect(provider.remotePathOf(node), '/srv/notes.txt');
    });

    test('корень тоже адресуется', () {
      expect(provider.rootDirectory.pathString, 'ssh://tester@example.org/');
      expect(provider.remotePathOf(provider.rootDirectory), '/');
    });

    test('разбирается и с началом адреса, и без него', () async {
      final withAuthority = await provider.resolvePath('//tester@example.org/srv/notes.txt').result;
      final plain = await provider.resolvePath('/srv/notes.txt').result;

      expect(withAuthority, isNotNull);
      expect(withAuthority!.pathString, plain!.pathString);
    });

    test('которого нет — null, а не ошибка', () async {
      expect(await provider.resolvePath('/srv/missing').result, isNull);
      expect(await provider.resolvePath('/srv/notes.txt/deeper').result, isNull);
    });

    test('цепочка узлов доходит до корня — панели есть куда идти наверх', () async {
      final node = await provider.resolvePath('/srv/www/index.html').result;

      expect(node!.path.map((n) => n.name).toList(), ['/', 'srv', 'www', 'index.html']);
      expect(identical(node.path.first, provider.rootDirectory), isTrue);
    });

    test('через ссылку на каталог — видимый путь идёт по ссылке', () async {
      final node = await provider.resolvePath('/srv/current/index.html').result;

      expect(node, isNotNull);
      expect(provider.remotePathOf(node!), '/srv/current/index.html');
      expect(node.pathString, 'ssh://tester@example.org/srv/current/index.html');
    });
  });

  group('чтение каталога', () {
    test('скрытое по умолчанию не показывается, «..» есть', () async {
      final dir = await open('/srv');
      final nodes = await provider.getDirectoryListing(dir).result;
      final names = nodes.map((node) => node.name).toList();

      expect(names.first, '..');
      expect(names, containsAll(['www', 'notes.txt', 'current', 'broken']));
      expect(names, isNot(contains('.hidden')));
    });

    test('скрытое по требованию показывается', () async {
      final dir = await open('/srv');
      final nodes = await provider.getDirectoryListing(dir, includeHidden: true).result;

      expect(nodes.map((node) => node.name), contains('.hidden'));
    });

    test('в корне «..» нет', () async {
      final nodes = await provider.getDirectoryListing(provider.rootDirectory).result;

      expect(nodes.map((node) => node.name), isNot(contains('..')));
    });

    test('ссылка знает про цель, битая — про то, что цели нет', () async {
      final dir = await open('/srv');
      final nodes = await provider.getDirectoryListing(dir).result;

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
      await provider.getDirectoryListing(dir).result;
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
        () => provider.getDirectoryListing(dir).result,
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.permissionDenied)),
      );
    });

    test('ссылка разворачивается в цель, а та помнит ссылку родителем', () async {
      final dir = await open('/srv');
      final nodes = await provider.getDirectoryListing(dir).result;
      final link = nodes.firstWhere((node) => node.name == 'current') as LinkNode;

      final target = await provider.resolveLink(link).result;

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
      final source = await provider.resolvePath('/srv/notes.txt').result;
      final destination = await open('/srv/www');

      expect(await provider.renameEntry(source!, destination, 'readme.txt'), isTrue);
      expect(server.has('/srv/www/readme.txt'), isTrue);
      expect(server.has('/srv/notes.txt'), isFalse);
    });

    test('в чужой источник переименованием не уехать', () async {
      final source = await provider.resolvePath('/srv/notes.txt').result;
      final elsewhere = InMemoryContentProvider();

      expect(await provider.renameEntry(source!, elsewhere.rootDirectory, 'readme.txt'), isFalse);
      expect(server.calls.where((call) => call.startsWith('rename')), isEmpty);
    });

    test('копии средствами сервера нет — движку сказано прямо', () async {
      final source = await provider.resolvePath('/srv/notes.txt').result;
      final destination = await open('/srv/www');

      expect(await provider.copyEntry(source!, destination, 'notes.txt'), isFalse);
    });

    test('удаляются и файл, и пустой каталог, и сама ссылка', () async {
      final file = await provider.resolvePath('/srv/notes.txt').result;
      await provider.deleteEntry(file!);
      expect(server.has('/srv/notes.txt'), isFalse);

      final link = await provider.resolvePath('/srv/current').result;
      await provider.deleteEntry(link!);
      expect(server.has('/srv/current'), isFalse);
      // Цель ссылки на месте: удаляли ссылку, а не то, куда она вела.
      expect(server.has('/srv/www'), isTrue);

      final directory = await provider.resolvePath('/srv/www/index.html').result;
      await provider.deleteEntry(directory!);
      await provider.deleteEntry((await open('/srv/www')));
      expect(server.has('/srv/www'), isFalse);
    });

    test('корзины и удаления поддерева нет — рекурсию ведёт движок', () async {
      final node = await provider.resolvePath('/srv/www').result;

      expect(await provider.trashEntry(node!), isFalse);
      expect(await provider.deleteTree(node), isFalse);
    });

    test('тот же объект и объект внутри себя', () async {
      final node = await provider.resolvePath('/srv/www').result;
      final srv = await open('/srv');

      expect(provider.isSameEntity(node!, srv), isTrue);
      expect(provider.isInsideSource(srv, srv), isTrue);
      expect(provider.isSameEntity(node, await open('/srv/www')), isFalse);
    });
  });

  group('байты', () {
    test('читается целиком и с середины', () async {
      final node = await provider.resolvePath('/srv/www/index.html').result;

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
      final node = await provider.resolvePath('/srv').result;

      final total = await provider.calculateSize([node!]).result;

      // <html/> (7) + заметки (14 байт в utf-8) + скрытое (14). Ссылки байтов
      // не переносят, у каталогов их нет.
      expect(total, 7 + utf8.encode('заметки').length + utf8.encode('скрытое').length);
    });

    test('обход считает и сам объект, и всё под ним', () async {
      final node = await provider.resolvePath('/srv/www').result;
      final sizes = <int>[];

      await provider.countEntries(node!, sizes.add);

      expect(sizes, hasLength(2)); // сам каталог и index.html
      expect(sizes.reduce((a, b) => a + b), 7);
    });

    test('закрытый подкаталог обход не обрывает', () async {
      server.directory('/srv/locked');
      server.file('/srv/locked/secret', 'x');
      server.denied['/srv/locked'] = FsErrorKind.permissionDenied;

      final node = await provider.resolvePath('/srv').result;
      final total = await provider.calculateSize([node!]).result;

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
      final source = await provider.resolvePath('/srv/notes.txt').result;

      await engine.copy([source!], local.rootDirectory).result;

      final copied = await local.resolvePath('/notes.txt').result;
      expect(copied, isNotNull);
      expect(utf8.decode(await _collect(await local.openRead(copied!))), 'заметки');
    });

    test('к себе целым каталогом', () async {
      final source = await provider.resolvePath('/srv/www').result;

      await engine.copy([source!], local.rootDirectory).result;

      expect(await local.resolvePath('/www/index.html').result, isNotNull);
    });

    test('от себя на сервер', () async {
      await local.createDirectory(local.rootDirectory, 'out');
      final outgoing = await local.resolvePath('/out').result as DirectoryNode;
      final sink = await local.openWrite(outgoing, 'report.txt', length: null);
      await sink.addStream(Stream<List<int>>.value(utf8.encode('отчёт')));
      await sink.close();

      final source = await local.resolvePath('/out/report.txt').result;
      final destination = await provider.resolvePath('/srv/www').result as DirectoryNode;

      await engine.copy([source!], destination).result;

      expect(server.contentOf('/srv/www/report.txt'), 'отчёт');
    });

    test('перенос внутри сервера идёт переименованием', () async {
      final source = await provider.resolvePath('/srv/notes.txt').result;
      final destination = await provider.resolvePath('/srv/www').result as DirectoryNode;

      await engine.move([source!], destination).result;

      expect(server.has('/srv/www/notes.txt'), isTrue);
      expect(server.has('/srv/notes.txt'), isFalse);
      expect(server.calls.where((call) => call.startsWith('rename')), hasLength(1));
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
