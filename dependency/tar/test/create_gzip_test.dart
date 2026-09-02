import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_tar/fc_tar.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Сжатие одного файла в `.gz`.
///
/// Разжимает результат **системный `gzip`**: свой провайдер `gz` проверяет тот
/// же поток тем же кодом, и сойтись на одинаковой ошибке им ничего не мешает.
void main() {
  late Directory work;
  late String source;
  late String target;
  late LocalTreeProvider disk;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('fc_gz_create');
    source = p.join(work.path, 'from');
    target = p.join(work.path, 'to');
    Directory(source).createSync();
    Directory(target).createSync();

    File(p.join(source, 'dump.sql')).writeAsStringSync('select 1;\n' * 100);
    Directory(p.join(source, 'src')).createSync();
    Link(p.join(source, 'link.sql')).createSync('dump.sql');

    disk = LocalTreeProvider(homePath: work.path, readInIsolate: false);
  });

  tearDown(() async {
    await work.delete(recursive: true);
  });

  Future<FsNode> nodeAt(String path) async => (await disk.resolvePath().run(path))!;

  /// Сжимает `from/<name>` в `to/<archive>`.
  Future<String> compress(String name, String archive) async {
    final command = CreateGzipCommand(staging: LocalStagingArea(root: work));
    final destination = await nodeAt(target) as DirectoryNode;

    await command.packOperation().run(GzipPackParams(await nodeAt(p.join(source, name)), destination, archive));

    final path = p.join(target, archive);
    expect(File(path).existsSync(), isTrue, reason: 'файл не появился');
    return path;
  }

  test('сжатое разжимается системным gzip', () async {
    final path = await compress('dump.sql', 'dump.sql.gz');

    // Заголовок gzip: два байта, по которым его узнают все.
    final head = await File(path).openRead(0, 2).expand((chunk) => chunk).toList();
    expect(head, [0x1f, 0x8b]);

    final result = await Process.run('gzip', ['-dc', path]);
    expect(result.exitCode, 0, reason: 'gzip: ${result.stderr}');
    expect(result.stdout, 'select 1;\n' * 100);
  });

  test('сжатое и правда меньше исходного', () async {
    final path = await compress('dump.sql', 'dump.sql.gz');

    expect(File(path).lengthSync(), lessThan(File(p.join(source, 'dump.sql')).lengthSync()));
  });

  test('свой провайдер видит внутри исходное имя и содержимое', () async {
    final path = await compress('dump.sql', 'dump.sql.gz');

    // Круг замкнулся: то, что мы сжали, открывается входом внутрь — и внутри
    // лежит файл с исходным именем.
    final provider = await GzipTreeProvider.open(await nodeAt(path));
    final node = (await provider.resolvePath().run('/dump.sql'))!;
    final bytes = await (provider as FileContentProvider).openRead(node);

    expect(node.size, 'select 1;\n'.length * 100, reason: 'размер берётся из хвоста gzip');
    expect(String.fromCharCodes(await bytes.expand((chunk) => chunk).toList()), 'select 1;\n' * 100);
  });

  test('ссылка сжимается по тому, куда ведёт', () async {
    // Класть в `.gz` саму ссылку нечего: имён внутри формата нет вовсе, и
    // ссылке там негде быть — есть только поток байтов.
    final path = await compress('link.sql', 'link.sql.gz');

    final result = await Process.run('gzip', ['-dc', path]);
    expect(result.stdout, 'select 1;\n' * 100);
  });

  test('каталог в .gz не кладётся', () async {
    // Даже вызовом со значением, мимо окна: формат жмёт поток, а каталог
    // потоком не бывает.
    await expectLater(
      compress('src', 'src.gz'),
      throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notSupported)),
    );
  });

  group('в палитре видна тогда, когда её есть на чём выполнить', () {
    late AppController app;

    setUp(() async {
      final memory = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/src'),
        FakeEntry.file('/home/dump.sql', size: 10),
        FakeEntry.file('/home/notes.txt', size: 10),
      ]);
      final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
      app = (await testApp(provider: memory, modules: [const TarArchiver()], settings: settings)).app;
      await app.start();
    });

    bool executable() => app.commands.isExecutable(app.commands.find(CreateGzipCommand.commandId)!);

    test('на файле — да', () {
      app.left.setCursorToName('dump.sql');

      expect(executable(), isTrue);
    });

    test('на каталоге — нет: каталог потоком не бывает, это к Mk Tar', () {
      app.left.setCursorToName('src');

      expect(executable(), isFalse);
    });

    test('на нескольких файлах — нет: в один .gz они не складываются', () {
      app.left.setCursorToName('dump.sql');
      app.left.selection.addAll(app.left.nodes.where((node) => node.name != '..'));

      expect(executable(), isFalse);
    });

    test('а Mk Tar на тех же нескольких — да', () {
      app.left.setCursorToName('dump.sql');
      app.left.selection.addAll(app.left.nodes.where((node) => node.name != '..'));

      // Ровно то различие, ради которого команды две: набор файлов — это tar.
      expect(app.commands.isExecutable(app.commands.find(CreateTarArchiveCommand.commandId)!), isTrue);
    });
  });

  test('имя по умолчанию — исходное плюс .gz', () async {
    // Расширение исходного файла остаётся на месте: по нему и понятно, что
    // внутри, а провайдер `gz` покажет ровно это имя.
    expect(CreateGzipCommand.defaultNameOf(await nodeAt(p.join(source, 'dump.sql'))), 'dump.sql.gz');
  });
}
