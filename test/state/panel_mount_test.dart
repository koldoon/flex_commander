import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/provider_registry.dart';
import 'package:flex_commander/model/tree/transfer/transfer_engine.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake/in_memory_tree_provider.dart';

/// Панель во вложенном источнике.
///
/// Войти в архив — это открыть каталог чужого провайдера, и ничего больше:
/// панель следует за каталогом, а тот приносит провайдера с собой.
void main() {
  late InMemoryContentProvider disk;
  late ProviderRegistry registry;
  late PanelController panel;

  List<FakeEntry> archiveEntries() => [
    FakeEntry.directory('/inner'),
    FakeEntry.file('/inner/doc.txt', content: [1, 2, 3]),
    FakeEntry.file('/readme.md', content: [4]),
  ];

  Future<PanelController> panelOn(ProviderRegistry source, {String path = '/home'}) async {
    final it = PanelController(provider: source.root, registry: source, settings: PanelSettings.defaults(path));
    addTearDown(it.dispose);
    await it.openPath(path);
    return it;
  }

  setUp(() async {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/archive.arc', content: [0]),
      FakeEntry.file('/home/notes.txt', size: 3),
    ]);
    registry = ProviderRegistry(root: disk)
      ..register('arc', (host) async => InMemoryArchiveProvider(archiveEntries(), host), extensions: {'arc'});
    panel = await panelOn(registry);
  });

  List<String> namesOf(PanelController of) => of.nodes.map((node) => node.name).toList();

  test('Enter на архиве показывает его содержимое', () async {
    panel.setCursorToName('archive.arc');

    expect(await panel.enterCurrent(), isNull);

    expect(namesOf(panel), containsAll(['inner', 'readme.md']));
    // Панель ушла в чужой провайдер, не зная о нём ничего.
    expect(panel.provider, isA<InMemoryArchiveProvider>());
  });

  test('файл, который открывать нечем, возвращается наверх', () async {
    panel.setCursorToName('notes.txt');

    // Им займётся система: панель не знает, что с ним делать.
    expect((await panel.enterCurrent())?.name, 'notes.txt');
    expect(panel.directory?.pathString, '/home');
  });

  test('путь панели показывает всю цепочку', () async {
    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();
    panel.setCursorToName('inner');
    await panel.enterCurrent();

    expect(panel.directory?.pathString, '/home/archive.arc:arc:/inner');
  });

  test('«..» из архива возвращает туда, где он лежит, и ставит на него курсор', () async {
    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();

    await panel.goUp();

    expect(panel.directory?.pathString, '/home');
    expect(panel.currentNode?.name, 'archive.arc');
    expect(panel.provider, same(disk));
  });

  test('внутри архива менять нечем, и панель это признаёт', () async {
    expect(panel.editor, isNotNull);

    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();

    // Примитивов изменения у архива нет — команды выключатся сами.
    expect(panel.editor, isNull);
  });

  test('сохранённый путь внутри архива открывается снова', () async {
    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();
    panel.setCursorToName('inner');
    await panel.enterCurrent();

    final saved = panel.settings.path;
    expect(saved, '/home/archive.arc:arc:/inner');

    // Другая панель, тот же реестр: архив монтируется заново по строке пути.
    final restored = await panelOn(registry, path: saved);

    expect(namesOf(restored), contains('doc.txt'));
    expect(restored.provider, isA<InMemoryArchiveProvider>());
  });

  test('битый архив оставляет панель на месте и говорит почему', () async {
    final broken = ProviderRegistry(root: disk)
      ..register('arc', (host) async => throw FsError(host.pathString, FsErrorKind.io), extensions: {'arc'});
    final it = await panelOn(broken);
    it.setCursorToName('archive.arc');

    expect(await it.enterCurrent(), isNull);

    expect(it.directory?.pathString, '/home');
    expect(it.status, PanelStatus.error);
    expect(it.error?.kind, FsErrorKind.io);
  });

  test('копирование из архива наружу идёт потоком', () async {
    panel.setCursorToName('archive.arc');
    await panel.enterCurrent();
    final inside = panel.nodes.firstWhere((node) => node.name == 'readme.md');
    final outside = (await disk.resolvePath('/home').result)! as DirectoryNode;

    // Источник и приёмник разных провайдеров: ни переименования, ни копии
    // средствами провайдера — только байты.
    await const TreeTransferEngine().copy([inside], outside).result;

    expect(await disk.resolvePath('/home/readme.md').result, isNotNull);
  });

  test('без реестра панель живёт в одном источнике, как раньше', () async {
    final plain = PanelController(provider: disk, settings: PanelSettings.defaults('/home'));
    addTearDown(plain.dispose);
    await plain.openPath('/home');
    plain.setCursorToName('archive.arc');

    // Открывать архив нечем: объект возвращается наверх как обычный файл.
    expect((await plain.enterCurrent())?.name, 'archive.arc');
  });
}
