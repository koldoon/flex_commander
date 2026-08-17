import 'dart:io';

import 'package:flex_commander/model/async/async_operation.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/local/local_tree_provider.dart';
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
    final dir = (await provider.resolvePath(root).result)! as DirectoryNode;
    final nodes = await provider.getDirectoryListing(dir).result;
    return {for (final node in nodes) node.name: node};
  }

  test('каталог считается вместе со всем содержимым', () async {
    final nodes = await listRoot();

    final total = await provider.calculateSize([nodes['docs']!]).result;

    expect(total, 300);
  });

  test('считаются все переданные объекты', () async {
    final nodes = await listRoot();

    final total = await provider.calculateSize([nodes['docs']!, nodes['notes.txt']!]).result;

    expect(total, 350);
  });

  test('промежуточные суммы приходят по ходу обхода', () async {
    final nodes = await listRoot();
    final operation = provider.calculateSize([nodes['docs']!]);
    final reports = <int>[];
    operation.progress.listen((event) => reports.add(event.processed));

    final total = await operation.result;
    await Future<void>.delayed(Duration.zero);

    // Сумма росла, а не появилась одним числом в конце.
    expect(reports.length, greaterThan(1));
    expect(reports, isNot(contains(greaterThan(total))));
    expect(reports.last, total);
  });

  test('в сообщении видно, чей размер считают', () async {
    final nodes = await listRoot();
    final operation = provider.calculateSize([nodes['docs']!]);
    final messages = <String>[];
    operation.progress.listen((event) => messages.add(event.message));

    await operation.result;
    await Future<void>.delayed(Duration.zero);

    expect(messages, everyElement('docs'));
  });

  test('ссылка на каталог не разворачивается', () async {
    final nodes = await listRoot();

    // Иначе содержимое каталога попало бы в сумму дважды.
    final total = await provider.calculateSize([nodes['link-to-docs']!]).result;

    expect(total, lessThan(300));
  });

  test('операцию можно прервать', () async {
    final nodes = await listRoot();
    final operation = provider.calculateSize([nodes['docs']!]);

    operation.cancel();

    await expectLater(operation.result, throwsA(isA<OperationCanceled>()));
  });

  test('недоступный каталог не срывает подсчёт', () async {
    final nodes = await listRoot();
    // Каталог исчез уже после того, как панель его показала.
    await Directory(p.join(root, 'docs')).delete(recursive: true);

    final total = await provider.calculateSize([nodes['docs']!, nodes['notes.txt']!]).result;

    expect(total, 50);
  });
}
