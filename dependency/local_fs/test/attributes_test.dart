import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Атрибуты объекта у локальной файловой системы: чтение и назначение.
///
/// Провайдер здесь тонкий — вся работа у системных вызовов, проверенных
/// отдельно, — но проверять всё равно есть что: что читается **сейчас**, а не
/// из узла, что умения объявлены честно и что перенос режима по-прежнему
/// молчит при отказе.
void main() {
  late Directory temp;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_attributes');
    provider = LocalTreeProvider(homePath: temp.path, readInIsolate: false);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<FsNode> node(String name, {String body = 'тело'}) async {
    final path = '${temp.path}/$name';
    await File(path).writeAsString(body, flush: true);
    return (await provider.resolvePath().run(path))!;
  }

  test('читает режим, даты и числа владельца', () async {
    final file = await node('plain.txt');

    final attributes = await provider.readAttributes(file);

    expect(attributes.modeString, startsWith('-'));
    expect(attributes.permissions, isNonZero);
    expect(attributes.uid, isNotNull);
    expect(attributes.gid, isNotNull);
    expect(attributes.modified, isNotNull);
    expect(attributes.accessed, isNotNull);
  });

  test('умения объявлены по тому, есть ли чем', () async {
    final attributes = await provider.readAttributes(await node('can.txt'));

    expect(attributes.canEditMode, isTrue);
    expect(attributes.canEditTimes, isTrue);
    expect(attributes.canEditOwner, isTrue);
    // Расширенные атрибуты кладёт не провайдер, а ядро: у него они спрашиваются
    // отдельным умением, и лишних системных вызовов здесь нет.
    expect(attributes.canEditXattrs, isFalse);
    expect(attributes.xattrs, isEmpty);
  });

  test('читает то, что сейчас, а не то, что было при чтении каталога', () async {
    final file = await node('fresh.txt');
    await Process.run('chmod', ['600', '${temp.path}/fresh.txt']);

    // Узел заведён до правки, и его собственные атрибуты устарели — именно
    // от этого и заведён отдельный вызов.
    expect((await provider.readAttributes(file)).permissions, 0x180);
  });

  test('назначает режим', () async {
    final file = await node('mode.txt');

    await provider.setMode(file, 0x1A0); // 0640

    expect((await provider.readAttributes(file)).permissions, 0x1A0);
  });

  test('назначает одну дату, не трогая вторую', () async {
    final file = await node('times.txt');
    final was = await provider.readAttributes(file);
    final when = DateTime.utc(2017, 7, 7, 7, 7, 7);

    await provider.setTimes(file, modified: when);

    final now = await provider.readAttributes(file);
    expect(now.modified!.toUtc(), when);
    expect(now.accessed, was.accessed);
  });

  test('несуществующего объекта нет и атрибутов', () async {
    final file = await node('gone.txt');
    await File('${temp.path}/gone.txt').delete();

    expect(
      () => provider.readAttributes(file),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notFound)),
    );
  });

  group('расширенные атрибуты', () {
    test('кладутся, читаются и убираются', () async {
      final file = await node('marked.txt');

      await provider.setXattr(file, 'com.example.note', utf8.encode('метка'));

      final read = await provider.readXattrs(file);
      expect(read.map((one) => one.name), ['com.example.note']);
      expect(read.single.text, 'метка');

      await provider.removeXattr(file, 'com.example.note');
      expect(await provider.readXattrs(file), isEmpty);
    });

    test('у чистого файла их нет', () async {
      expect(await provider.readXattrs(await node('clean.txt')), isEmpty);
    });
  });

  group('словарь пользователей', () {
    test('своё число разбирается в имя и обратно', () async {
      final uid = int.parse((await Process.run('id', ['-u'])).stdout.toString().trim());
      final name = (await Process.run('id', ['-un'])).stdout.toString().trim();

      expect(await provider.userName(uid), name);
      expect(await provider.userId(name), uid);
    });

    test('неизвестное имя — null', () async {
      expect(await provider.userId('такого-точно-нет'), isNull);
    });
  });

  group('перенос режима', () {
    test('переносит то, что стоит сейчас', () async {
      final from = await node('source.txt');
      final to = await node('target.txt');
      await Process.run('chmod', ['600', '${temp.path}/source.txt']);
      await Process.run('chmod', ['644', '${temp.path}/target.txt']);

      await provider.carryMode(from: from, to: to);

      expect((await provider.readAttributes(to)).permissions, 0x180);
    });

    test('молчит, когда переносить нечего', () async {
      final from = await node('vanished.txt');
      final to = await node('kept.txt');
      await File('${temp.path}/vanished.txt').delete();

      // Это сохранность прав, а не само сохранение файла: ронять из-за неё
      // уже записанное хуже, чем оставить права по умолчанию.
      await expectLater(provider.carryMode(from: from, to: to), completes);
    });
  });
}
