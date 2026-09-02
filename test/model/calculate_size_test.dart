import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_local_fs/backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Подсчёт размера на настоящей файловой системе.
void main() {
  late Directory temp;
  late String root;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_size');
    root = await temp.resolveSymbolicLinks();

    await Directory(p.join(root, 'docs')).create();
    await Directory(p.join(root, 'docs', 'nested')).create();
    await File(p.join(root, 'docs', 'a.txt')).writeAsBytes(List.filled(100, 0));
    await File(p.join(root, 'docs', 'nested', 'b.txt')).writeAsBytes(List.filled(200, 0));
    await File(p.join(root, 'notes.txt')).writeAsBytes(List.filled(50, 0));
    await Link(p.join(root, 'link-to-docs')).create(p.join(root, 'docs'));

    provider = LocalTreeProvider(homePath: root, readInIsolate: false);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<Map<String, FsNode>> listRoot() async {
    final dir = (await provider.resolvePath().run(root))! as DirectoryNode;
    final nodes = await provider.getDirectoryListing().run(ListingParams(dir));
    return {for (final node in nodes) node.name: node};
  }

  test('каталог считается вместе со всем содержимым', () async {
    final nodes = await listRoot();

    final total = await provider.calculateSize().run([nodes['docs']!]);

    expect(total, 300);
  });

  test('считаются все переданные объекты', () async {
    final nodes = await listRoot();

    final total = await provider.calculateSize().run([nodes['docs']!, nodes['notes.txt']!]);

    expect(total, 350);
  });

  test('промежуточные суммы приходят по ходу обхода', () async {
    final nodes = await listRoot();
    final operation = provider.calculateSize();
    final log = ProgressLog.of(operation);

    operation.start([nodes['docs']!]);
    final total = await operation.result;
    await Future<void>.delayed(Duration.zero);

    // Сумма росла, а не появилась одним числом в конце.
    final counted = log.reports.map((report) => report.itemsTransferred).toList();
    expect(counted.length, greaterThan(1));
    expect(counted, isNot(contains(greaterThan(total))));
    expect(counted.last, total);
  });

  test('в сообщении видно, чей размер считают', () async {
    final nodes = await listRoot();
    final operation = provider.calculateSize();
    final log = ProgressLog.of(operation);

    operation.start([nodes['docs']!]);
    await operation.result;
    await Future<void>.delayed(Duration.zero);

    expect(log.reports.map((report) => report.message), everyElement('docs'));
  });

  test('ссылка на каталог не разворачивается', () async {
    final nodes = await listRoot();

    // Иначе содержимое каталога попало бы в сумму дважды.
    final total = await provider.calculateSize().run([nodes['link-to-docs']!]);

    expect(total, lessThan(300));
  });

  test('скрытые файлы и каталоги считаются наравне с остальными', () async {
    // Панель может их не показывать, но размер каталога от этого не меняется —
    // именно так считает и сама система.
    await File(p.join(root, 'docs', '.hidden.txt')).writeAsBytes(List.filled(7, 0));
    await Directory(p.join(root, 'docs', '.cache')).create();
    await File(p.join(root, 'docs', '.cache', 'inside.bin')).writeAsBytes(List.filled(13, 0));
    final nodes = await listRoot();

    final total = await provider.calculateSize().run([nodes['docs']!]);

    expect(total, 300 + 7 + 13);
  });

  test('недоступный подкаталог не обрывает подсчёт остального', () async {
    // Закрытых каталогов в macOS хватает (~/Library и соседи), и первая же
    // такая папка обрывала обход: всё, что стояло после неё, в сумму не
    // попадало — молча и незаметно.
    final tree = Directory(p.join(root, 'tree'))..createSync();
    var expected = 0;
    final locked = <String>[];

    // Вперемешку: порядок обхода каталога задаёт файловая система, и полагаться
    // на него нельзя.
    for (var i = 0; i < 10; i++) {
      await File(p.join(tree.path, 'file-$i.txt')).writeAsBytes(List.filled(100 + i, 0));
      expected += 100 + i;

      final closed = p.join(tree.path, 'locked-$i');
      await Directory(closed).create();
      await File(p.join(closed, 'secret.bin')).writeAsBytes(List.filled(1000, 0));
      await Process.run('chmod', ['000', closed]);
      locked.add(closed);
    }
    // Иначе временный каталог не удалить.
    addTearDown(() async {
      for (final path in locked) {
        await Process.run('chmod', ['755', path]);
      }
    });

    final nodes = await listRoot();
    final total = await provider.calculateSize().run([nodes['tree']!]);

    // Недоступное не посчитано — прочитать его нечем; всё остальное на месте.
    expect(total, expected);
  });

  test('счётчик объектов задания тоже не спотыкается о закрытый каталог', () async {
    // Тот же обход, но ради числа объектов: по нему рисуется доля в окне
    // операции, и оборванный счёт превратил бы её в ложь.
    final tree = Directory(p.join(root, 'tree'))..createSync();
    final locked = p.join(tree.path, 'locked');
    await Directory(locked).create();
    await File(p.join(locked, 'secret.bin')).writeAsBytes(List.filled(1000, 0));
    await Process.run('chmod', ['000', locked]);
    addTearDown(() => Process.run('chmod', ['755', locked]));

    for (var i = 0; i < 5; i++) {
      await File(p.join(tree.path, 'file-$i.txt')).writeAsBytes(List.filled(10, 0));
    }

    final nodes = await listRoot();
    var entries = 0;
    var bytes = 0;
    await provider.countEntries(nodes['tree']!, (size) {
      entries++;
      bytes += size;
    });

    // Сам каталог, пять файлов и закрытый каталог; внутрь него не заглянуть.
    expect(entries, 7);
    expect(bytes, 50);
  });

  test('операцию можно прервать', () async {
    final nodes = await listRoot();
    final operation = provider.calculateSize();

    operation.cancel();

    operation.start([nodes['docs']!]);
    await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
  });

  test('недоступный каталог не срывает подсчёт', () async {
    final nodes = await listRoot();
    // Каталог исчез уже после того, как панель его показала.
    await Directory(p.join(root, 'docs')).delete(recursive: true);

    final total = await provider.calculateSize().run([nodes['docs']!, nodes['notes.txt']!]);

    expect(total, 50);
  });
}
