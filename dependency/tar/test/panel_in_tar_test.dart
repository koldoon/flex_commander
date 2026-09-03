import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_tar/fc_tar.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Панель внутри tar — и внутри `.tar.gz` цепочкой.
///
/// Здесь проверяется то, ради чего провайдера два: человек нажимает `Enter` на
/// `src.tar.gz`, потом `Enter` на `src.tar` — и оказывается в дереве. Никакого
/// особого случая для двойного расширения в коде нет, работает выбор провайдера
/// по расширению.
void main() {
  late Directory work;
  late String root;
  late LocalTreeProvider disk;
  late ProviderRegistry registry;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('fc_tar_panel');
    root = work.path;

    final source = Directory(p.join(root, 'src'))..createSync();
    Directory(p.join(source.path, 'lib')).createSync();
    File(p.join(source.path, 'readme.md')).writeAsStringSync('# hello');
    File(p.join(source.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}');

    for (final arguments in [
      ['-cf', 'src.tar', 'src'],
      ['-czf', 'src.tar.gz', 'src'],
      ['-czf', 'src.tgz', 'src'],
    ]) {
      final result = await Process.run('tar', arguments, workingDirectory: root);
      expect(result.exitCode, 0, reason: 'tar: ${result.stderr}');
    }

    disk = LocalTreeProvider(homePath: root, readInIsolate: false);
    registry =
        ProviderRegistry(root: disk)
          ..register(
            TarTreeProvider.schemeName,
            () => TaskOperation<FsNode, TreeProvider>(
              (op, host) => TarTreeProvider.open(host, staging: const LocalStagingArea()),
            ),
            extensions: TarTreeProvider.extensions,
          )
          ..register(
            GzipTreeProvider.schemeName,
            () => TaskOperation<FsNode, TreeProvider>((op, host) => GzipTreeProvider.open(host)),
            extensions: GzipTreeProvider.extensions,
          );
  });

  tearDown(() async {
    await work.delete(recursive: true);
  });

  Future<TestPanel> panelAtRoot() async {
    final panel = testPanel(provider: disk, registry: registry, settings: PanelSettings.defaults(root));
    addTearDown(panel.dispose);
    await panel.openPath(root);
    return panel;
  }

  test('Enter на .tar показывает содержимое', () async {
    final panel = await panelAtRoot();
    panel.setCursorToName('src.tar');

    expect(await panel.enterCurrent(), isNull);

    expect(panel.session.provider, isA<TarTreeProvider>());
    expect(panel.entries.map((node) => node.name), containsAll(['..', 'src']));
  });

  test('в .tar.gz входят дважды: сперва в сжатое, потом в архив', () async {
    final panel = await panelAtRoot();
    panel.setCursorToName('src.tar.gz');

    expect(await panel.enterCurrent(), isNull);
    // Первое звено: сжатый поток показывает ровно одну запись — сам архив.
    expect(panel.session.provider, isA<GzipTreeProvider>());
    expect(panel.entries.map((node) => node.name), containsAll(['..', 'src.tar']));

    panel.setCursorToName('src.tar');
    expect(await panel.enterCurrent(), isNull);

    // Второе звено: здесь поток и разжимается на диск — ровно один раз, и
    // делает это тот, кому нужен настоящий файл.
    expect(panel.session.provider, isA<TarTreeProvider>());
    panel.setCursorToName('src');
    expect(await panel.enterCurrent(), isNull);
    expect(panel.entries.map((node) => node.name), containsAll(['lib', 'readme.md']));
  });

  test('.tgz открывается так же', () async {
    final panel = await panelAtRoot();
    panel.setCursorToName('src.tgz');

    expect(await panel.enterCurrent(), isNull);

    expect(panel.entries.map((node) => node.name), containsAll(['..', 'src.tar']));
  });

  test('путь внутри архива переживает перезапуск', () async {
    final panel = await panelAtRoot();
    panel.setCursorToName('src.tar');
    await panel.enterCurrent();
    panel.setCursorToName('src');
    await panel.enterCurrent();

    final saved = panel.session.settings.path;
    final restored = testPanel(provider: disk, registry: registry, settings: PanelSettings.defaults(saved));
    addTearDown(restored.dispose);

    expect(await restored.openPath(saved), isTrue);
    expect(restored.entries.map((node) => node.name), contains('readme.md'));
  });

  test('выход из архива убирает временную копию', () async {
    final panel = await panelAtRoot();
    panel.setCursorToName('src.tar.gz');
    await panel.enterCurrent();
    panel.setCursorToName('src.tar');
    await panel.enterCurrent();

    final provider = panel.session.provider as TarTreeProvider;
    expect(File(provider.archivePath).existsSync(), isTrue, reason: 'поток разжат во временный файл');

    // Наружу одним прыжком: закрыться должны оба звена.
    expect(await panel.openPath(root), isTrue);
    // Закрытие асинхронное: панель не ждёт его, чтобы показать каталог. А
    // уборка временной копии идёт на диск — оборотами очереди её не ускорить,
    // и на сборочной машине их не хватало (упал CI выпуска v0.0.50). Тот же
    // случай и то же лекарство, что в `zip_tree_provider_test.dart`.
    await waitUntilAsync(() async => !await File(provider.archivePath).exists());

    expect(File(provider.archivePath).existsSync(), isFalse, reason: 'копия живёт не дольше архива');
  });
}
