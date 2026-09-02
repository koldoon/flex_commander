import 'dart:convert';
import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Локальные копии чужих файлов и время их жизни.
void main() {
  late Directory temp;
  late String root;
  late LocalTreeProvider disk;
  late LocalCopySession session;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_copy');
    root = await temp.resolveSymbolicLinks();
    await File(p.join(root, 'notes.txt')).writeAsString('текст файла');

    disk = LocalTreeProvider(homePath: root, readInIsolate: false);
    session = LocalCopySession(const LocalStagingArea());
  });

  tearDown(() async {
    await session.purge();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Файл в источнике без настоящих путей: скопировать его придётся.
  Future<FsNode> remoteFile({List<int>? content}) async {
    final memory = InMemoryArchiveProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/remote.bin', content: content ?? utf8.encode('содержимое')),
    ]);
    return (await memory.resolvePath().run('/home/remote.bin'))!;
  }

  test('настоящий путь отдаётся как есть, без копирования', () async {
    final node = (await disk.resolvePath().run(p.join(root, 'notes.txt')))!;

    expect(await session.localPathOf(node), p.join(root, 'notes.txt'));
    // Ровно за этим и заведён realFileSystem: копировать то, что и так лежит
    // на диске, незачем.
    expect(session.copied, 0);
  });

  test('чужой файл оказывается во временном', () async {
    final path = await session.localPathOf(await remoteFile());

    expect(path, isNot('/home/remote.bin'));
    expect(await File(path).readAsString(), 'содержимое');
    expect(session.copied, 1);
  });

  test('о ходе копирования сообщается по кускам', () async {
    final seen = <int>[];

    await session.localPathOf(await remoteFile(content: List.filled(35, 7)), onBytes: seen.add);

    // Куски, а не один итог: копия большого архива идёт заметное время.
    expect(seen.length, greaterThan(1));
    expect(seen.fold<int>(0, (sum, bytes) => sum + bytes), 35);
  });

  test('purge убирает всё, что накопировано', () async {
    final path = await session.localPathOf(await remoteFile());
    expect(await File(path).exists(), isTrue);

    await session.purge();

    expect(await File(path).exists(), isFalse);
    expect(await Directory(p.dirname(path)).exists(), isFalse);
  });

  test('purge можно звать дважды: и из finally, и из dispose', () async {
    await session.localPathOf(await remoteFile());

    await session.purge();
    await session.purge();
  });

  test('убранной сессией больше не пользуются', () async {
    await session.purge();

    await expectLater(session.localPathOf(await remoteFile()), throwsA(isA<FsError>()));
  });

  test('без копий убирать нечего — и каталог не заводится', () async {
    final node = (await disk.resolvePath().run(p.join(root, 'notes.txt')))!;
    await session.localPathOf(node);

    await session.purge();

    // Временный каталог создаётся только под первую настоящую копию.
    expect(session.copied, 0);
  });

  test('источник без байтов копировать нечем', () async {
    final memory = InMemoryReadOnlyProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/remote.bin', content: [1, 2, 3]),
    ]);
    final node = (await memory.resolvePath().run('/home/remote.bin'))!;

    await expectLater(
      session.localPathOf(node),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notSupported)),
    );
  });

  test('оборвавшееся копирование не оставляет обрезанного файла', () async {
    // Сперва удачная копия — по ней и найдём временный каталог сессии.
    final directory = Directory(p.dirname(await session.localPathOf(await remoteFile())));
    expect(directory.listSync(), hasLength(1));

    final broken = _BreakingProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/remote.bin', content: List.filled(50, 1)),
    ]);
    final node = (await broken.resolvePath().run('/home/remote.bin'))!;

    await expectLater(session.localPathOf(node), throwsA(anything));

    // Половина файла под настоящим именем выглядит как целый — её убирают
    // сразу, не дожидаясь purge.
    expect(directory.listSync(), hasLength(1));
  });
}

/// Источник, чтение которого обрывается на первом же куске.
class _BreakingProvider extends InMemoryArchiveProvider {
  _BreakingProvider([super.entries]);

  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final content = await super.openRead(node, offset: offset);
    return () async* {
      await for (final chunk in content) {
        yield chunk;
        throw const FormatException('сеть оборвалась');
      }
    }();
  }
}
