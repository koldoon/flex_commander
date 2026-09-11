import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ftp/fc_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ftp.dart';

/// Провайдер над подставным сервером: дерево, пути, отказы.
void main() {
  late FakeFtp ftp;
  late FtpTreeProvider provider;

  setUp(() {
    ftp = FakeFtp(
      directories: {'/pub', '/pub/inner'},
      files: {
        '/pub/notes.txt': utf8.encode('заметки'),
        '/pub/inner/deep.bin': utf8.encode('глубоко'),
        '/pub/.hidden': utf8.encode('скрытое'),
      },
    );
    provider = FtpTreeProvider(target: FtpTarget.parse(Uri.parse('ftp://user@host/pub')), ftp: ftp);
  });

  Future<DirectoryNode> directory(String path) async => await provider.resolvePath().run(path) as DirectoryNode;

  group('пути', () {
    test('путь несёт адрес целиком — из него панель и восстановится', () async {
      final node = await provider.resolvePath().run('/pub/notes.txt');

      expect(provider.pathOf(node!), '//user@host/pub/notes.txt');
      expect(provider.remotePathOf(node), '/pub/notes.txt');
    });

    test('путь с началом адреса разбирается так же, как без него', () async {
      expect(await provider.resolvePath().run('//user@host/pub'), isA<DirectoryNode>());
      expect(await provider.resolvePath().run('/pub'), isA<DirectoryNode>());
    });

    test('корень отдаётся без обращения к серверу', () async {
      final root = await provider.resolvePath().run('/');

      expect(root, same(provider.rootDirectory));
      expect(ftp.calls, isEmpty, reason: 'за корнем ходить некуда');
    });

    test('несуществующего пути нет', () async {
      expect(await provider.resolvePath().run('/pub/нет.txt'), isNull);
    });

    test('промежуточный файл в пути — это не каталог', () async {
      expect(await provider.resolvePath().run('/pub/notes.txt/дальше'), isNull);
    });
  });

  group('список каталога', () {
    test('каталоги, файлы и «..»', () async {
      final dir = await directory('/pub');
      final nodes = await provider.getDirectoryListing().run(ListingParams(dir));

      expect(nodes.first, isA<ParentDirNode>());
      expect(nodes.whereType<DirectoryNode>().map((node) => node.name), contains('inner'));
      expect(nodes.whereType<FileNode>().map((node) => node.name), contains('notes.txt'));
    });

    test('скрытое показывается по просьбе', () async {
      final dir = await directory('/pub');

      final plain = await provider.getDirectoryListing().run(ListingParams(dir));
      expect(plain.map((node) => node.name), isNot(contains('.hidden')));

      final all = await provider.getDirectoryListing().run(ListingParams(dir, includeHidden: true));
      expect(all.map((node) => node.name), contains('.hidden'));
    });

    test('у корня «..» нет', () async {
      final nodes = await provider.getDirectoryListing().run(ListingParams(provider.rootDirectory));

      expect(nodes.whereType<ParentDirNode>(), isEmpty);
    });

    test('размер и права доходят до строки', () async {
      final dir = await directory('/pub');
      final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
      final file = nodes.whereType<FileNode>().firstWhere((node) => node.name == 'notes.txt');

      expect(file.size, utf8.encode('заметки').length);
      expect(file.attributes.modeString, '-rw-r--r--');
    });

    test('обход не пишет в узел того, что показывает панель', () async {
      final dir = await directory('/pub');

      final children = await provider.listChildren(dir);
      expect(children.whereType<ParentDirNode>(), isEmpty, reason: 'обходу «..» не нужен');
      expect(dir.nodes, isEmpty, reason: 'список панели обходом не подменяется');
    });
  });

  group('умения', () {
    test('работа ровно одна: канал у FTP один', () {
      expect(provider.capabilities.maxConcurrency, 1);
    });

    test('докачка обещается только тогда, когда сервер объявил REST', () {
      expect(provider.capabilities.canSeek, isTrue);

      final without = FtpTreeProvider(
        target: FtpTarget.parse(Uri.parse('ftp://host/')),
        ftp: FakeFtp(features: FtpFeatures(['SIZE'])),
      );
      expect(without.capabilities.canSeek, isFalse);
    });

    test('пути сервера снаружи ничего не значат', () {
      expect(provider.capabilities.realFileSystem, isFalse);
    });
  });

  group('чтение и запись', () {
    test('байты читаются целиком и с середины', () async {
      final node = await provider.resolvePath().run('/pub/notes.txt');

      expect(utf8.decode(await _collect(await provider.openRead(node!))), 'заметки');
      final tail = await _collect(await provider.openRead(node, offset: 2));
      expect(tail, utf8.encode('заметки').sublist(2));
    });

    test('запись кладёт файл в каталог', () async {
      final dir = await directory('/pub');

      final sink = await provider.openWrite(dir, 'new.txt');
      sink.add(utf8.encode('новое'));
      await sink.close();

      expect(utf8.decode(ftp.files['/pub/new.txt']!), 'новое');
    });
  });

  group('изменение дерева', () {
    test('каталог создаётся', () async {
      final dir = await directory('/pub');

      final created = await provider.createDirectory(dir, 'свежий');
      expect(created.name, 'свежий');
      expect(ftp.directories, contains('/pub/свежий'));
    });

    test('занятое имя — это «уже существует», а не отказ сервера', () async {
      // Отдельного кода «уже существует» у FTP нет: сервер отвечает общим
      // отказом, по которому не отличить занятое имя от нехватки прав.
      final dir = await directory('/pub');

      await expectLater(
        provider.createDirectory(dir, 'inner'),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.alreadyExists)),
      );
    });

    test('дурное имя до сервера не доходит', () async {
      final dir = await directory('/pub');

      for (final name in ['', '.', '..', 'с/косой']) {
        await expectLater(
          provider.createDirectory(dir, name),
          throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.invalidName)),
        );
      }
      expect(ftp.calls.where((call) => call.startsWith('mkdir')), isEmpty);
    });

    test('переименование внутри сервера идёт одним действием', () async {
      final node = await provider.resolvePath().run('/pub/notes.txt');
      final dir = await directory('/pub/inner');

      expect(await provider.renameEntry(node!, dir, 'moved.txt'), isTrue);
      expect(ftp.files, contains('/pub/inner/moved.txt'));
    });

    test('переименование в чужой источник — «так не умею»', () async {
      final node = await provider.resolvePath().run('/pub/notes.txt');
      final elsewhere = DirectoryNode(
        provider: FtpTreeProvider(target: FtpTarget.parse(Uri.parse('ftp://other/')), ftp: FakeFtp()),
        name: '/',
      );

      expect(await provider.renameEntry(node!, elsewhere, 'x'), isFalse, reason: 'движок скопирует сам');
    });

    test('удаление различает файл и каталог', () async {
      final file = await provider.resolvePath().run('/pub/notes.txt');
      await provider.deleteEntry(file!);
      expect(ftp.calls, contains('rm /pub/notes.txt'));

      final dir = await directory('/pub/inner');
      await provider.deleteEntry(dir);
      expect(ftp.calls, contains('rmdir /pub/inner'));
    });

    test('поддерево и корзина — не к нам', () async {
      final dir = await directory('/pub');

      expect(await provider.deleteTree(dir), isFalse, reason: 'рекурсию ведёт движок — он и покажет ход');
      expect(await provider.trashEntry(dir), isFalse, reason: 'корзины на сервере нет');
    });

    test('копия средствами сервера не обещается', () async {
      final node = await provider.resolvePath().run('/pub/notes.txt');
      final dir = await directory('/pub/inner');

      expect(await provider.copyEntry(node!, dir, 'x'), isFalse);
    });
  });

  group('отказы сервера', () {
    test('доходят как есть, а не превращаются в пустой список', () async {
      ftp.refusals['/pub'] = FsErrorKind.permissionDenied;
      final dir = await directory('/');

      await expectLater(
        provider.listChildren(DirectoryNode(provider: provider, name: 'pub', parent: dir)),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.permissionDenied)),
      );
    });
  });

  test('закрытие провайдера закрывает соединение', () async {
    await provider.dispose();

    expect(ftp.closed, isTrue);
  });
}

Future<List<int>> _collect(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return bytes;
}
